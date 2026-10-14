# alfred-contacts-cli-workflow

An [Alfred](https://www.alfredapp.com/) workflow for searching the contacts you've imported with [contacts-cli](https://github.com/quintrino/contacts-cli).

Type `contacts` and part of a name, number, email or organisation:

| Key | Does |
| --- | --- |
| `↩` | Copies the number to the clipboard |
| `⌘↩` | Messages it with the app chosen in the workflow settings (`--signal` by default, or `--sms`, `--whatsapp`, ...) |
| `⇧↩` | Opens a `mailto:` link to the contact's first email. Holding `⇧` shows the email in place of the subtitle |

A contact with several numbers gets a row per number, so you choose which one to copy or message; `⇧↩` emails the contact whichever row it is on. A contact with no number shows its first email instead, and one with neither is listed but can't be selected. A contact with a number but no email shows "No email address" while `⇧` is held, and `⇧↩` does nothing.

## Install

1. Install contacts-cli and import your contacts (Google Contacts → **Export** → **Google CSV**):

   ```sh
   brew install quintrino/tap/contacts-cli
   contacts-cli import ~/Downloads/contacts.csv
   ```

2. Download `Contacts-CLI.alfredworkflow` from the [latest release](https://github.com/quintrino/alfred-contacts-cli-workflow/releases/latest) and open it. Alfred adds the workflow. Workflows need Alfred's [Powerpack](https://www.alfredapp.com/powerpack/).

## Settings

Open the workflow in Alfred and click **[𝑥]** (Configure Workflow):

| Setting | Default | |
| --- | --- | --- |
| **Message with** | Signal | What `⌘↩` does. Every `contacts-cli message` flag is offered: Signal, WhatsApp, Telegram, iMessage, SMS, FaceTime, Phone call and Email. The subtitle under a result shows the current choice while `⌘` is held. |
| **contacts-cli path** | *(blank)* | Leave blank and the workflow finds contacts-cli on its own, checking `/opt/homebrew/bin`, `/usr/local/bin` and your `PATH`. Fill it in only for an install somewhere else. |

To change the `contacts` keyword, double-click the **Search contacts** object in the workflow.

On macOS, `⌘↩` opens the link in the app itself: for Signal that is `Signal`, or `Signal Beta` if that's the one installed (see contacts-cli's README for the other apps). `--email` writes to the contact's first email, and the other flags use the number you selected.

## How it works

```
contacts ──► Script Filter ──↩──► Copy to Clipboard ──► notification
 (keyword)   scripts/search.sh
                    └────────⌘↩──► Run Script ──► notification
                                   scripts/message.sh
                    └────────⇧↩──► Open URL  mailto:<email>
```

- `scripts/search.sh` runs `contacts-cli search --format json`, which prints the matching contacts as a plain JSON array (`name`, `phones`, `emails`, `organization`, `notes`). Nothing about it is specific to Alfred.
- `scripts/to_script_filter.pl` turns that array into Alfred's Script Filter rows. This is where everything Alfred-specific lives: one row per phone number, the row's `arg` (the number, which Enter copies and ⌘↩ messages), the first email under the `shift` modifier, the "Message with …" subtitle for the configured flag, and the rows for contacts with nothing to act on or for no matches. It uses only Perl and `JSON::PP`, which macOS ships, so there is nothing else to install.
- `scripts/message.sh` runs `contacts-cli message <flag> -- <number>`. `message` finds the contact again by that number, then opens the app. Its last line (or, on failure, the reason) is shown in a notification.
- `⇧↩` needs no script: each row carries the contact's first email, and an Open URL object opens `mailto:` with it.
- If contacts-cli is missing, too old to know `--format json`, errors out (for example on a corrupt contacts file), or prints something that isn't a JSON array, the search shows a single row saying what's wrong instead of nothing.

Alfred starts scripts with a bare `PATH` that leaves out Homebrew, which is why the scripts look for contacts-cli themselves.

## Development

```sh
bash tests/test.sh      # runs the scripts against a fake contacts-cli, and checks info.plist
bash scripts/build.sh   # writes dist/Contacts-CLI.alfredworkflow (needs zip)
```

The tests need neither Alfred nor the real contacts-cli. CI runs them on macOS, so they use the same bash 3.2 as Alfred, lints `info.plist` with `plutil`, and publishes the packaged workflow as a GitHub release on every push to the default branch.

To edit the workflow, import it, change it in Alfred, then copy the exported `info.plist` back here. The scripts in `scripts/` are plain files and can be edited directly.
