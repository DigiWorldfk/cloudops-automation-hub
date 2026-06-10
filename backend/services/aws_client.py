import os
import asyncio
import boto3
from typing import List, Optional
import logging

logger = logging.getLogger(__name__)

AWS_REGION = os.getenv("AWS_DEFAULT_REGION", "us-east-1")


def _ec2():
    return boto3.client("ec2", region_name=AWS_REGION)

def _ssm():
    return boto3.client("ssm", region_name=AWS_REGION)

def _ce():
    return boto3.client("ce", region_name="us-east-1")


async def aws_list_instances() -> List[dict]:
    def _list():
        ec2 = _ec2()
        resp = ec2.describe_instances()
        instances = []
        for r in resp.get("Reservations", []):
            for i in r.get("Instances", []):
                name = next((t["Value"] for t in i.get("Tags", []) if t["Key"] == "Name"), None)
                instances.append({
                    "instance_id":        i.get("InstanceId"),
                    "instance_type":      i.get("InstanceType"),
                    "state":              i.get("State", {}).get("Name"),
                    "availability_zone":  i.get("Placement", {}).get("AvailabilityZone"),
                    "private_ip":         i.get("PrivateIpAddress"),
                    "public_ip":          i.get("PublicIpAddress"),
                    "name":               name,
                    "launch_time":        str(i.get("LaunchTime")),
                })
        return instances
    return await asyncio.to_thread(_list)


async def aws_create_instance(ami_id: str, instance_type: str, subnet_id: str,
                               security_group_ids: List[str], key_name: Optional[str],
                               name_tag: str) -> dict:
    def _create():
        ec2 = _ec2()
        kwargs = dict(
            ImageId=ami_id,
            InstanceType=instance_type,
            SubnetId=subnet_id,
            SecurityGroupIds=security_group_ids,
            MinCount=1, MaxCount=1,
            TagSpecifications=[{"ResourceType": "instance", "Tags": [{"Key": "Name", "Value": name_tag}]}],
        )
        if key_name:
            kwargs["KeyName"] = key_name
        resp = ec2.run_instances(**kwargs)
        iid = resp["Instances"][0]["InstanceId"]
        return {"instance_id": iid, "state": "pending", "name": name_tag}
    return await asyncio.to_thread(_create)


async def aws_terminate_instance(instance_id: str) -> dict:
    def _term():
        _ec2().terminate_instances(InstanceIds=[instance_id])
        return {"status": "terminating", "instance_id": instance_id}
    return await asyncio.to_thread(_term)


async def aws_start_instance(instance_id: str) -> dict:
    def _start():
        _ec2().start_instances(InstanceIds=[instance_id])
        return {"status": "starting", "instance_id": instance_id}
    return await asyncio.to_thread(_start)


async def aws_stop_instance(instance_id: str) -> dict:
    def _stop():
        _ec2().stop_instances(InstanceIds=[instance_id])
        return {"status": "stopping", "instance_id": instance_id}
    return await asyncio.to_thread(_stop)


async def aws_resize_instance(instance_id: str, instance_type: str) -> dict:
    def _resize():
        ec2 = _ec2()
        ec2.stop_instances(InstanceIds=[instance_id])
        waiter = ec2.get_waiter("instance_stopped")
        waiter.wait(InstanceIds=[instance_id])
        ec2.modify_instance_attribute(InstanceId=instance_id, InstanceType={"Value": instance_type})
        ec2.start_instances(InstanceIds=[instance_id])
        return {"status": "resized", "instance_id": instance_id, "instance_type": instance_type}
    return await asyncio.to_thread(_resize)


async def aws_snapshot_instance(instance_id: str, description: str) -> dict:
    def _snapshot():
        ec2 = _ec2()
        resp = ec2.describe_instances(InstanceIds=[instance_id])
        volumes = resp["Reservations"][0]["Instances"][0].get("BlockDeviceMappings", [])
        snaps = []
        for bdm in volumes:
            vid = bdm["Ebs"]["VolumeId"]
            snap = ec2.create_snapshot(VolumeId=vid, Description=description)
            snaps.append(snap["SnapshotId"])
        return {"status": "snapshot_initiated", "snapshots": snaps}
    return await asyncio.to_thread(_snapshot)


async def aws_create_volume(instance_id: str, size_gb: int, volume_type: str, availability_zone: str) -> dict:
    def _vol():
        ec2 = _ec2()
        vol = ec2.create_volume(Size=size_gb, VolumeType=volume_type, AvailabilityZone=availability_zone)
        vid = vol["VolumeId"]
        waiter = ec2.get_waiter("volume_available")
        waiter.wait(VolumeIds=[vid])
        # attach to /dev/xvdf (or next available)
        ec2.attach_volume(VolumeId=vid, InstanceId=instance_id, Device="/dev/xvdf")
        return {"status": "attached", "volume_id": vid, "instance_id": instance_id}
    return await asyncio.to_thread(_vol)


async def aws_run_patch_baseline(instance_id: str) -> dict:
    def _patch():
        ssm = _ssm()
        resp = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunPatchBaseline",
            Parameters={"Operation": ["Install"]},
        )
        cmd_id = resp["Command"]["CommandId"]
        return {"status": "patch_initiated", "command_id": cmd_id, "instance_id": instance_id}
    return await asyncio.to_thread(_patch)


async def aws_patch_status(instance_id: str, command_id: str) -> dict:
    def _status():
        ssm = _ssm()
        resp = ssm.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
        return {
            "status":         resp.get("StatusDetails"),
            "stdout":         resp.get("StandardOutputContent", "")[-2000:],
            "stderr":         resp.get("StandardErrorContent", "")[-500:],
        }
    return await asyncio.to_thread(_status)


async def aws_get_costs(period_days: int = 30) -> dict:
    def _costs():
        from datetime import date, timedelta
        end   = date.today().isoformat()
        start = (date.today() - timedelta(days=period_days)).isoformat()
        ce = _ce()
        resp = ce.get_cost_and_usage(
            TimePeriod={"Start": start, "End": end},
            Granularity="MONTHLY",
            Metrics=["BlendedCost"],
        )
        return resp.get("ResultsByTime", [])
    return await asyncio.to_thread(_costs)
