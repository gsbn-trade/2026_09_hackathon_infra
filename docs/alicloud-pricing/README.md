# AliCloud ECS pricing — what `ecs.g9i.2xlarge` actually costs

What's confirmed, what isn't, and how to get an exact number — written up
because the obvious ways to check (console calculator, search engines) all
came up short for this specific instance type/region combo.

## Confirmed

- **Spec**: `ecs.g9i.2xlarge` = 8 vCPU / 32 GiB RAM (official docs — see
  [Alibaba Cloud's general-purpose instance family
  page](https://www.alibabacloud.com/help/en/ecs/user-guide/general-purpose-instance-families)).
  This is the size `infra/variables.tf` defaults to (bumped from
  `ecs.g9i.xlarge`, 4 vCPU/16GB, to fit the full 5-team replication — see
  [ARCHITECTURE.md](../../ARCHITECTURE.md)).
- **Mainland China (Beijing/华北2) pay-as-you-go reference rate**:
  **¥1.9884/hour** (~$0.27/hr, ~$196/month at 24/7) — found via a
  third-party aggregator's price table, cross-checked for internal
  consistency: `g9i.large` (2 vCPU) lists ¥0.4971/hr, and 0.4971 × 4 =
  1.9884, which is exactly what a linear per-vCPU rate within one instance
  family should look like. `g9i.32xlarge` (128 vCPU) lists ¥31.8136/hr,
  close to the same linear projection (0.4971 × 64 = 31.8144) — small
  rounding, not a different pricing curve.

## NOT confirmed — don't quote this as the real number

That ¥1.9884/hour is a **mainland China (Beijing) rate**, not
`cn-hongkong`. Alibaba Cloud's Hong Kong region is generally priced higher
than mainland regions (international bandwidth/infrastructure costs), but
no verified HK-specific multiplier was found — treat the mainland figure
as a rough floor, not an estimate to budget against.

Two avenues were tried and both came up short for a definitive HK number:

1. **The console/public pricing calculator** is JS-rendered — `WebFetch`
   gets an empty shell, no price data in the static HTML. Search engines
   don't have it indexed either (g9i is new enough that most third-party
   aggregators — sparecores.com, vantage.sh-style sites — have the spec
   but not the price for this exact instance type).
2. **Alibaba's own pricing API, called directly**, which would have been
   authoritative:
   ```bash
   aliyun bssopenapi GetPayAsYouGoPrice \
     --ProductCode ecs \
     --ProductType ecs \
     --SubscriptionType PayAsYouGo \
     --Region cn-hongkong \
     --ModuleList.1.ModuleCode InstanceType \
     --ModuleList.1.PriceType Hour \
     --ModuleList.1.Config "InstanceType:ecs.g9i.2xlarge,IoOptimized:IoOptimized,ImageOs:linux,Region:cn-hongkong,NetworkType:vpc"
   ```
   This is the right shape (confirmed via `aliyun help bssopenapi
   GetPayAsYouGoPrice` — no parameter errors), but the `default` profile's
   RAM user only has `AliyunECSFullAccess`/`AliyunVPCFullAccess` (see
   [README.md](../../README.md)'s Configuration steps log) — it returned
   `NotAuthorized`, not a price.

## To get the exact number

Either of these, whichever is less friction:

- **Console calculator**, region set to Hong Kong, instance type
  `ecs.g9i.2xlarge`: <https://www.alibabacloud.com/en/pricing/calculator>
- **Grant `AliyunBSSReadOnlyAccess`** to the RAM user in the
  [RAM console](https://ram.console.alibabacloud.com/users) (same place
  [docs/alicloud-api-key/](../alicloud-api-key/) attaches
  `AliyunBailianControlFullAccess` for the same profile), then re-run the
  `aliyun bssopenapi GetPayAsYouGoPrice` command above — it's ready to go,
  just missing that one permission.

## Other line items — not part of the instance's own rate

The instance price alone isn't the whole bill. `infra/main.tf` also
provisions, separately billed:

- **EIP bandwidth** — `PayByTraffic`, 20 Mbps peak (`eip_bandwidth` in
  `terraform.tfvars`). The instance itself has `internet_max_bandwidth_out
  = 0` — the EIP is the only public egress path, so this is real, not
  incidental.
- **System disk** — 100GB `cloud_essd` (`system_disk_size` in `main.tf`).

For a few-day event, `tofu destroy` right after teardown (see
[README.md](../../README.md#tearing-down-after-the-event)) means you only
pay for the hours everything actually ran — none of this is a monthly
commitment.
