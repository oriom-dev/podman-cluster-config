"""Run on the secured Windows issuer, never on the VPS. No private keys are transferred."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--issuer", type=Path, required=True, help="Secured sd_2607/appview/bsaf directory")
    parser.add_argument("--key", type=Path, required=True, help="SSH deployment key")
    parser.add_argument("--publish-current", action="store_true", help="Publish an already freshly signed snapshot")
    args = parser.parse_args()
    issuer = args.issuer.resolve(strict=True)
    key = args.key.resolve(strict=True)
    private = issuer / "private"
    run = lambda argv, **kwargs: subprocess.run(argv, check=True, timeout=90, **kwargs)
    # Fail closed before reading/signing with the local root. This audit checks every
    # file against the explicitly provisioned Windows user SID, including backups.
    run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(private / "verify-private-acl.ps1")])
    node = shutil.which("node")
    if not node:
        raise RuntimeError("Node.js 24 required on the issuer")
    if not args.publish_current:
        previous = json.loads((private / "snapshot-state.json").read_text())["body"]
        archive = private / "snapshot-history" / ("sequence-" + str(previous["sequence"]))
        archive.mkdir(parents=True, exist_ok=True)
        for name in ("snapshot-state.json", "snapshot.cbor"):
            source, destination = private / name, archive / name
            if destination.exists():
                if destination.read_bytes() != source.read_bytes():
                    raise RuntimeError("Archived snapshot differs; operator review required")
            else:
                with destination.open("xb") as output:
                    output.write(source.read_bytes())
        run([node, "identity-cli.mjs", "snapshot"], cwd=issuer)
    # Independently validate signature, current expiry and canonical published bytes.
    check = """import fs from 'node:fs';
import {verifySnapshot,canonical} from '../../pds/public-information.mjs';
const s=JSON.parse(fs.readFileSync('private/snapshot-state.json'));
const roots=JSON.parse(fs.readFileSync('private/roots.json'));
await verifySnapshot(s,{root:roots[0],nowSeconds:Math.floor(Date.now()/1000)});
if(!Buffer.from(canonical(s)).equals(fs.readFileSync('private/snapshot.cbor')))throw Error('Snapshot bytes differ');
"""
    run([node, "--input-type=module", "-e", check], cwd=issuer)
    options = ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=15", "-i", str(key)]
    host = "operator@133.18.180.180"
    run(["ssh", *options, host, "install -d -m 0700 /home/operator/.cache/mosimo-snapshot"])
    run(["scp", *options, str(private / "snapshot.cbor"), host + ":/home/operator/.cache/mosimo-snapshot/snapshot.cbor"])
    digest = hashlib.sha256((private / "snapshot.cbor").read_bytes()).hexdigest()
    # Copy to a root-owned temporary file before checking, then atomically replace.
    # Readers always get either complete version; no sequence or CRL state is reset.
    command = (
        "sudo install -o root -g caddy -m 0640 /home/operator/.cache/mosimo-snapshot/snapshot.cbor /var/lib/mosimo-trust/snapshot.cbor.next"
        " && echo '" + digest + "  /var/lib/mosimo-trust/snapshot.cbor.next' | sudo sha256sum --check --status"
        " && sudo mv /var/lib/mosimo-trust/snapshot.cbor.next /var/lib/mosimo-trust/snapshot.cbor"
        " && rm /home/operator/.cache/mosimo-snapshot/snapshot.cbor"
    )
    run(["ssh", *options, host, command])
    state = json.loads((private / "snapshot-state.json").read_text())["body"]
    print(json.dumps({"publishedSequence": state["sequence"], "validUntil": state["validUntil"]}))


if __name__ == "__main__":
    main()
