# SSH to the ECS VM: what broke, what was tried, what actually worked

Record of a real debugging session (2026-09-02) where SSH from the
operator's own Mac to the hackathon VM (and to unrelated hosts like
GitHub) failed consistently — written up because the root cause turned
out to be local to the operator's machine, not the VM, and the detour
through several VM-side theories is worth keeping so it isn't re-walked
next time this comes up.

## Symptom

```
$ ssh root@8.210.203.139
kex_exchange_identification: read: Operation timed out
banner exchange: Connection to 8.210.203.139 port 22: Operation timed out
```

Consistent, from the operator's real terminal, regardless of source IP,
regardless of VPN on/off, regardless of destination port.

## What was actually wrong

**The operator's Mac has JumpCloud's Endpoint Security agent installed and
active** (`com.jumpcloud.jcagent-tray.EndpointSecurity`, confirmed via
`systemextensionsctl list` — enabled, activated). JumpCloud is corporate
device-management software; its Endpoint Security extension uses Apple's
official EndpointSecurity framework, which can intercept and block
specific process/network behavior at the OS level — SSH-blocking is a
real, documented policy some orgs enable (Zero Trust / conditional-access
style: no unaudited shell access from managed devices). This is upstream
of anything in this repo or on the VM to fix; it needs the org's JumpCloud
admin/console.

**Confirmed, not inferred**, by the decisive test: `ssh -T git@github.com`
(a totally unrelated, always-reachable host) failed with the *exact same*
`kex_exchange_identification: read: Operation timed out` error — including
over GitHub's own port-443 SSH endpoint (the standard trick for networks
that block port 22 specifically), and both with the operator's VPN
connected and disconnected. A failure that's identical across three
independent destinations/ports/VPN-states, but only for the SSH protocol
specifically (plain HTTPS/curl to arbitrary hosts worked fine throughout),
points at something local and protocol-aware, not a path/routing issue to
any one host.

## What was tried first, on the (wrong) assumption this was VM/network-side

Kept here because each step is a real, reusable diagnostic technique for
"is my VM okay?", even though none of them were the actual fix this time:

1. **Security group review** (`aliyun ecs DescribeSecurityGroupAttribute`)
   — confirmed 22/80/443 rules exactly matched `infra/main.tf`. Ruled out.
2. **EIP association check** (`aliyun vpc DescribeEipAddresses`) — `InUse`,
   correctly bound. Ruled out.
3. **MTU mismatch theory**: `eth0` came up at `mtu 8500` (jumbo frames,
   normal for this instance family's VPC NIC) after a stop/start cycle,
   with no ICMP allowed inbound in the security group — a classic PMTUD
   blackhole shape. Lowered to 1500 via
   `aliyun ecs RunCommand` (`ip link set eth0 mtu 1500`). Didn't fix it,
   but this is a real, independently-worth-having fix — left in place.
4. **Packet capture on the VM's own NIC** (`tcpdump` via `RunCommand`,
   timed around real connection attempts) — this is what actually
   redirected the investigation. It showed the full TCP handshake
   completing, both sides exchanging plaintext SSH banners correctly, sshd
   healthy and responsive (`SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.16`
   sent within 2ms) — then the *client's* address sending a RST ~25ms
   later, before key exchange ever started. Looked at the time like
   on-path SSH-protocol blocking (a real, documented category of
   middlebox behavior) — reasonable given this project's Hong
   Kong/mainland-China context, but see below.
5. **Alternate SSH port (2222)**: added `Port 2222` to `sshd_config`
   (now baked into `infra/cloud-init.sh` for future fresh deploys) and a
   matching security group rule (`infra/main.tf`'s `ssh_alt_port*`
   resources). Failed identically. Ruled out port-based blocking
   specifically.
6. **Host-side firewall check**: `iptables -L INPUT` empty with `ACCEPT`
   policy, `ufw inactive`, no `fail2ban` — the VM has zero firewall rules
   of its own. Ruled out anything host-side.
7. **Cloud Assistant Session Manager + `ali-instance-cli portforward`**:
   tunneled the VM's port 22 to `localhost:2022` entirely over Alibaba's
   own control-plane channel, bypassing the public EIP/internet path
   completely. `ssh -p 2022 root@127.0.0.1` **still failed identically** —
   the single most important data point, since a channel with zero public
   internet exposure failing the same way meant the problem couldn't be
   "somewhere between the internet and the VM" at all.
8. **Raw byte-level check over that same tunnel**: `nc 127.0.0.1 2022`
   read the complete, correct SSH banner instantly. Data transits the
   tunnel fine — only the `ssh` *client process* fails on it.
9. **`ssh -vvv`** on that clean tunnel showed the client forming its own
   banner (`Local version string SSH-2.0-OpenSSH_10.2`) and then hanging
   on the read — with `Darwin 25.5.0` and `/Users/kirill/...` visible in
   the debug output, confirming these commands were running as the
   operator's own real shell the whole time, not an isolated sandbox as
   first assumed.
10. **The decisive test**: `ssh -T git@github.com` (nothing to do with
    this project's infrastructure at all) failed identically. That's when
    the investigation redirected from "what's wrong with the VM" to
    "what's wrong with this Mac" — and found the JumpCloud extension.

## What this means for actually operating the VM

SSH from this specific machine isn't coming back without a JumpCloud
policy change on the org's side. Until/unless that happens, use:

- **`aliyun ecs RunCommand`** (Cloud Assistant) for one-off remote
  commands — no SSH involved at all, confirmed reliable throughout this
  entire investigation. Pattern:
  ```bash
  aliyun ecs RunCommand --region cn-hongkong --Type RunShellScript \
    --InstanceId.1 <instance-id> \
    --CommandContent "$(echo -n '<script>' | base64)" --ContentEncoding Base64
  # then poll:
  aliyun ecs DescribeInvocationResults --region cn-hongkong --InvokeId <id>
  ```
- **`ali-instance-cli portforward`** for anything that needs a real TCP
  tunnel (rsync, a database client, etc.) without SSH:
  ```bash
  ./ali-instance-cli portforward -i <instance-id> --region cn-hongkong \
    --profile default -r <remote-port> -l <local-port>
  ```
  Download: `curl -O https://aliyun-client-assist.oss-accelerate.aliyuncs.com/session-manager/mac/ali-instance-cli`
  (macOS build; there's a `linux_arm` path alongside it in the same
  bucket for other platforms). Requires Cloud Assistant's Session Manager
  feature enabled once per account:
  `aliyun ecs ModifyCloudAssistantSettings --RegionId cn-hongkong --SettingType SessionManagerConfig --SessionManagerConfig '{"SessionManagerEnabled":true}'`
  (confirmed off by default; this session turned it on).
- **`ali-instance-cli session`** (a full interactive shell over the same
  channel) needs a real TTY — doesn't work from a non-interactive
  execution context, but should work fine from an operator's own regular
  terminal window.
- **File transfer without `scp`/`rsync`-over-ssh**: two mechanisms, used in
  this order in practice (2026-09-02):
  1. **One-time bootstrap**: `rsync --daemon` on the VM bound to
     `127.0.0.1` (via `RunCommand`), tunneled to with `portforward`, then
     `rsync` from the operator's machine to
     `rsync://localhost:<port>/<module>/` — same transfer semantics as
     `deploy.sh`'s normal SSH-based rsync, just a different transport
     underneath. Used to get the very first copy of `app/` and `data/`
     across before git was set up. Slow (relay overhead — ~4.5MB took
     over 3 minutes) but reliable; worth excluding anything not actually
     needed (`app/dify/`, evaluated-and-dropped per ARCHITECTURE.md, was
     68MB/~7800 files of unnecessary weight the first time).
  2. **Ongoing updates, once git is set up** (the actual steady state):
     the VM has its own git checkout at `/opt/repo` (not `/opt/app`
     directly — `/opt/app` is only the `app/` subdirectory of this repo,
     so cloning straight into it would nest the whole tree inside itself;
     confirmed the hard way, caught by git's own "dubious ownership"
     safety check before anything was overwritten). Cloned over HTTPS
     using a fine-grained, read-only, repo-scoped GitHub token (GitHub
     deploy keys are disabled org-wide — confirmed via
     `gh repo deploy-key add` returning "Deploy keys are disabled for
     this repository" — so a PAT is the only automatable option) stored
     in `/root/.git-credentials` via `git config --global
     credential.helper store`. To apply an update:
     ```bash
     # via RunCommand, no SSH needed anywhere in this sequence:
     git -C /opt/repo pull
     rsync -a --exclude=".env" --exclude="team-credentials.txt" \
       --exclude="docker-compose.override.yml" /opt/repo/app/ /opt/app/
     cd /opt/app && docker compose up -d --build
     ```
     The `rsync` here is a **local** copy on the VM itself (`/opt/repo` →
     `/opt/app`, same filesystem) — instant, no tunnel, no relay overhead.
     `/opt/app` is deliberately kept as a real directory rather than a
     symlink to `/opt/repo/app`: several containers (DeepSeek Harness in
     particular) have it bind-mounted while live, and Docker resolves a
     bind mount's host path at container-create time — swapping the
     directory out from under an already-running mount is a real way to
     disrupt a live session for no benefit a local rsync doesn't already
     give you.

## Next steps if a real fix (not a workaround) is wanted

- Check with whoever administers this org's JumpCloud console for a
  policy specifically restricting SSH client connections, and whether an
  exception can be scoped to this use case.
- If JumpCloud isn't actually the cause (not fully proven — the
  EndpointSecurity extension being *present and enabled* is strong
  circumstantial evidence, but no explicit "blocked by JumpCloud" log line
  was captured; `log show` in this environment returned `too many
  arguments` on every attempt, including with no predicate at all, so the
  unified log was never actually queried successfully), the next
  diagnostic step is temporarily disabling the JumpCloud agent (if
  policy/IT allows) and re-testing `ssh -T git@github.com` — a clean
  success immediately after disabling it would close this out completely.
