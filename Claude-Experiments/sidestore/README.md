# SideStore: keeping WHOOP Buzz signed without the Mac

Set up 9 October 2026 on the owner's iPhone 15 (iOS 27.0, build 24A437).

A free Apple account signs an app for 7 days. Before this, WHOOP Buzz had to be rebuilt and reinstalled from the Mac every week. SideStore re-signs apps on the phone itself, and each refresh resets the 7 days.

## What is installed

| Item | Detail |
|---|---|
| SideStore | 0.7.0 alpha (build 20260911), bundle `com.SideStore.SideStore.<TEAM-ID>`, installed from the Mac with iloader 2.3.6 |
| LocalDevVPN | From the App Store. SideStore needs it connected while it installs or refreshes |
| WHOOP Buzz | Bundle `dev.yajat.WhoopBuzzResearch.<TEAM-ID>`, installed by SideStore from `WhoopBuzz-main.ipa` (Release build of the main sources as of 11:03 that day) |
| Apple account | The same one Xcode uses (team `<TEAM-ID>`). SideStore added its own certificate and did not revoke Xcode's |

The phone allows three free-signed apps in total. They are now another development app, SideStore and WHOOP Buzz. A second development app and the Xcode-installed WHOOP Buzz were removed to make room.

## The refresh automation

Shortcut "Refresh SideStore", four actions:

1. Set VPN: Connect to LocalDevVPN
2. Wait 5 seconds
3. Refresh All Apps (SideStore's action)
4. Set VPN: Disconnect from LocalDevVPN

A Time of Day automation runs that shortcut daily, set to Run Immediately.

Tested the same day:

| Time | Test | Result |
|---|---|---|
| 13:36 | Shortcut run by hand | Both apps refreshed in 5.4 s |
| 14:11 | Time of Day automation, phone locked and on USB | SideStore started fresh in the background and refreshed both apps in 6.2 s. Expiry moved to 16 October 03:11 UTC |

Not yet seen: a run with the phone unplugged, and whether it keeps firing night after night.

## What the nightly run needs

At the scheduled time:

- Wi-Fi with internet. The Mac is not involved, and it does not have to be the home network. SideStore's docs say mobile data is not suitable. Only the owner's home Wi-Fi has been tried.
- The phone switched on and unlocked at least once since its last restart. Locked is fine.
- The automation switched on and set to Run Immediately.

Staying in place:

- LocalDevVPN installed. It does not need to be left connected; the shortcut connects and disconnects it.
- SideStore installed and still signed in to the Apple account.
- Developer Mode left on in Settings.

## What can break it, and the fix

| Problem | Effect | Fix |
|---|---|---|
| More than 7 days without a successful refresh | Both apps expire and SideStore will not open | Reinstall SideStore with iloader on the Mac, then refresh |
| iOS update or reset | SideStore's pairing file may stop working, so refreshes fail | Replace the pairing file with iloader on the Mac |
| Apple asks SideStore to sign in again | Refreshes fail until it is done | Open SideStore and sign in |
| Another VPN connected at that hour | LocalDevVPN cannot connect | Disconnect the other VPN, or move the schedule |
| Apple changes its sign-in servers | Older SideStore builds cannot sign in (this happened in September 2026) | Update SideStore |

Weekly habit that covers all of these: look at SideStore's day counter. If it is not near 7, connect LocalDevVPN and tap refresh.

iloader is not kept in this repo. Download it from https://iloader.app; the official steps are at https://docs.sidestore.io/docs/installation/install.

## Checking from the Mac

With the phone on USB:

```sh
./check-refresh.sh
```

Prints SideStore's recent refresh runs from its own log: when each started, the new expiry for each app, and how long it took. Read-only.

## Updating the app

Do not install the Xcode build with `devicectl install`. It would arrive as a fourth free-signed app under the old bundle ID and the phone refuses it. Updates go in through SideStore, which replaces the app in place and keeps its data and the Shortcuts automation.

```sh
./make-ipa.sh --push            # build ../../WhoopBuzz and copy the .ipa to the phone
./make-ipa.sh --push ../WhoopCalls   # or build another copy of the project
```

Then on the phone, with LocalDevVPN connected: SideStore, My Apps, +, On My iPhone, SideStore, and pick the file.

`make-ipa.sh` without `--push` was tested and produced a valid .ipa. The `--push` copy uses the same command that placed `WhoopBuzz-main.ipa` on the phone.

## Other files here

- `WhoopBuzz-main.ipa` — the file SideStore installed.
- `before-signing-state.txt` — the Mac's signing certificates and profiles just before SideStore was set up.
- `old-app-final-log.txt` — the Xcode-installed app's last saved log before it was removed.
- `build-main/` — the copy of the main sources that `WhoopBuzz-main.ipa` was built from.
