# ✨ SkyWanderer Loyalty System - Alpha

**Version:** `0.2.3`
**Contract Language:** [Clarity](https://docs.stacks.co/write-smart-contracts/clarity-overview)
**Purpose:** A decentralized loyalty points system that rewards users for long-term participation and point lockup commitment using \$VOYAGER-POINTS.

---

## 🚀 Overview

The **SkyWanderer Loyalty System** is a smart contract-based loyalty mechanism that incentivizes users ("Voyagers") to lock STX and earn loyalty points over time. Users are ranked into tiers based on the total amount they lock, with additional multipliers based on the lock duration.

Points earned are minted as a fungible token: `VOYAGER-POINTS`.

---

## 🛠 Features

* ✅ Lock STX to start earning VOYAGER-POINTS.
* ⏳ Rewards grow over time and are boosted by commitment length and rank.
* 🏆 Rank-based system: Explorer, Elite, and Platinum tiers.
* ⛔ Safety toggles to pause operations or activate protocol overrides.
* 🔐 Cooldown and exit requests required before unlocking funds.
* 💰 Reward claiming system based on blocks passed since last claim.

---

## 🧱 Data Structures

### Maps

* **`VoyagerAccount`**

  * Stores locked points, earned points, last activity, and rank information.

* **`JourneyPlan`**

  * Tracks ongoing point locks, duration, exit requests, and claim timestamps.

* **`RankTiers`**

  * Defines the point requirements and benefit multipliers for each rank level.

---

## 🪙 Token

* **`VOYAGER-POINTS`** (Fungible Token)

  * Minted as rewards based on participation.

---

## 🔧 Public Functions

### System Setup

* `setup-system()`: Initializes rank tiers (admin-only).

### Lock & Rewards

* `lock-points(amount, time-period)`: Locks STX and starts reward earning.
* `claim-rewards()`: Claims rewards based on elapsed time and rank.

### Exit Process

* `request-exit(amount)`: Starts cooldown timer before withdrawal.
* `complete-exit(amount)`: Completes withdrawal after cooldown expires.

### Admin Controls

* `update-system-status(paused)`: Pauses/unpauses contract (admin-only).
* `toggle-safety-protocol(active)`: Toggles emergency protocol (admin-only).

---

## 🧮 Reward Calculation

Rewards are calculated as:

```
base = (locked-points × blocks-passed × standard-rate) / 1,000,000
boosted = (base × rank-boost) / 100
```

### Time-Based Boost Multipliers:

| Lock Duration            | Multiplier |
| ------------------------ | ---------- |
| ≥ 2 months (8640 blocks) | 1.5x       |
| ≥ 1 month (4320 blocks)  | 1.25x      |
| < 1 month                | 1x         |

---

## 🎖 Rank System

| Rank     | Points Locked | Rank Boost |
| -------- | ------------- | ---------- |
| Explorer | ≥ 1M          | 1.0x (100) |
| Elite    | ≥ 5M          | 1.5x (150) |
| Platinum | ≥ 10M         | 2.0x (200) |

---

## 🧩 Errors

| Code    | Description               |
| ------- | ------------------------- |
| `u5001` | Access denied (non-admin) |
| `u5002` | Locked during operation   |
| `u5003` | Invalid points            |
| `u5004` | Insufficient funds        |
| `u5005` | Lockup still active       |
| `u5006` | Account not found         |
| `u5007` | Threshold not met         |
| `u5008` | System paused             |

---

## ✅ Deployment Checklist

* [ ] Deploy `VOYAGER-POINTS` token (if not already on-chain).
* [ ] Run `setup-system()` as the admin.
* [ ] Use `update-system-status(false)` to unpause the system.
* [ ] Configure front-end or CLI interactions for `lock-points`, `claim-rewards`, and exits.

---

## 🔐 Admin Key

Admin rights are currently defined as the **contract deployer** (`tx-sender` at deploy time). All sensitive functions (setup, pause, safety toggle) are restricted.

---

## 📌 Notes

* Block timings assume \~10 minutes per block.
* Users must request exits before claiming locked STX.
* Rank boosts and time multipliers stack multiplicatively.
