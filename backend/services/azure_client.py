import os
import asyncio
from typing import List, Optional
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient
from azure.mgmt.compute.models import (
    VirtualMachine, HardwareProfile, StorageProfile, OSProfile,
    NetworkProfile, NetworkInterfaceReference, OSDisk, ImageReference,
    ManagedDiskParameters, DiskCreateOptionTypes, VirtualMachineSizeTypes,
)
from azure.mgmt.network import NetworkManagementClient
import logging

logger = logging.getLogger(__name__)

SUBSCRIPTION_ID = os.getenv("AZURE_SUBSCRIPTION_ID", "")


def _get_compute_client() -> ComputeManagementClient:
    return ComputeManagementClient(DefaultAzureCredential(), SUBSCRIPTION_ID)


def _get_network_client() -> NetworkManagementClient:
    return NetworkManagementClient(DefaultAzureCredential(), SUBSCRIPTION_ID)


async def azure_list_vms() -> List[dict]:
    def _list():
        client = _get_compute_client()
        vms = []
        for vm in client.virtual_machines.list_all():
            # get instance view for power state
            try:
                view = client.virtual_machines.instance_view(
                    vm.id.split("/")[4], vm.name
                )
                statuses = view.statuses or []
                power = next(
                    (s.display_status for s in statuses if s.code.startswith("PowerState/")),
                    "unknown",
                )
            except Exception:
                power = "unknown"
            vms.append({
                "name":           vm.name,
                "resource_group": vm.id.split("/")[4],
                "location":       vm.location,
                "vm_size":        vm.hardware_profile.vm_size if vm.hardware_profile else None,
                "status":         power,
                "os_type":        str(vm.storage_profile.os_disk.os_type) if vm.storage_profile and vm.storage_profile.os_disk else None,
            })
        return vms

    return await asyncio.to_thread(_list)


async def azure_create_vm(rg: str, name: str, location: str, vm_size: str,
                           image: str, admin_user: str, admin_pass: str) -> dict:
    def _create():
        compute = _get_compute_client()
        network = _get_network_client()
        # create NIC (assumes default VNet/subnet exist; extend as needed)
        nic_name = f"{name}-nic"
        vnet_name   = os.getenv("AZURE_DEFAULT_VNET", "cloudops-vnet")
        subnet_name = os.getenv("AZURE_DEFAULT_SUBNET", "default")
        nic_params  = {
            "location": location,
            "ip_configurations": [{
                "name": "ipconfig1",
                "subnet": {"id": f"/subscriptions/{SUBSCRIPTION_ID}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet_name}/subnets/{subnet_name}"},
                "public_ip_address": None,
            }],
        }
        nic_poller = network.network_interfaces.begin_create_or_update(rg, nic_name, nic_params)
        nic = nic_poller.result()

        image_ref = ImageReference(publisher="Canonical", offer="UbuntuServer", sku="18.04-LTS", version="latest")
        vm_params = VirtualMachine(
            location=location,
            hardware_profile=HardwareProfile(vm_size=vm_size),
            storage_profile=StorageProfile(
                image_reference=image_ref,
                os_disk=OSDisk(create_option=DiskCreateOptionTypes.FROM_IMAGE, managed_disk=ManagedDiskParameters(storage_account_type="Standard_LRS")),
            ),
            os_profile=OSProfile(computer_name=name, admin_username=admin_user, admin_password=admin_pass),
            network_profile=NetworkProfile(network_interfaces=[NetworkInterfaceReference(id=nic.id, primary=True)]),
        )
        poller = compute.virtual_machines.begin_create_or_update(rg, name, vm_params)
        vm = poller.result()
        return {"name": vm.name, "resource_group": rg, "location": vm.location, "status": "created"}

    return await asyncio.to_thread(_create)


async def azure_delete_vm(rg: str, name: str) -> dict:
    def _delete():
        compute = _get_compute_client()
        compute.virtual_machines.begin_delete(rg, name).result()
        return {"status": "deleted", "name": name}
    return await asyncio.to_thread(_delete)


async def azure_start_vm(rg: str, name: str) -> dict:
    def _start():
        compute = _get_compute_client()
        compute.virtual_machines.begin_start(rg, name).result()
        return {"status": "started", "name": name}
    return await asyncio.to_thread(_start)


async def azure_stop_vm(rg: str, name: str) -> dict:
    def _stop():
        compute = _get_compute_client()
        compute.virtual_machines.begin_deallocate(rg, name).result()
        return {"status": "deallocated", "name": name}
    return await asyncio.to_thread(_stop)


async def azure_resize_vm(rg: str, name: str, vm_size: str) -> dict:
    def _resize():
        compute = _get_compute_client()
        vm = compute.virtual_machines.get(rg, name)
        vm.hardware_profile.vm_size = vm_size
        compute.virtual_machines.begin_create_or_update(rg, name, vm).result()
        return {"status": "resized", "name": name, "vm_size": vm_size}
    return await asyncio.to_thread(_resize)


async def azure_snapshot_vm(rg: str, vm_name: str, snapshot_name: str) -> dict:
    def _snapshot():
        compute = _get_compute_client()
        vm = compute.virtual_machines.get(rg, vm_name)
        disk_id = vm.storage_profile.os_disk.managed_disk.id
        snapshot_params = {
            "location": vm.location,
            "creation_data": {"create_option": "Copy", "source_resource_id": disk_id},
        }
        compute.snapshots.begin_create_or_update(rg, snapshot_name, snapshot_params).result()
        return {"status": "snapshot_created", "snapshot": snapshot_name}
    return await asyncio.to_thread(_snapshot)


async def azure_expand_disk(rg: str, disk_name: str, size_gb: int) -> dict:
    def _expand():
        compute = _get_compute_client()
        disk = compute.disks.get(rg, disk_name)
        disk.disk_size_gb = size_gb
        compute.disks.begin_create_or_update(rg, disk_name, disk).result()
        return {"status": "expanded", "disk": disk_name, "size_gb": size_gb}
    return await asyncio.to_thread(_expand)
