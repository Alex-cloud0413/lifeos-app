# Security and data boundaries

Life · OS is development software. This source release has not undergone an independent security audit.

- Cloud builds use the developer's own CloudKit private database; the repository contains no hosted database, personal task data, signing identity, model key, or account credentials.
- Preview uses local storage. Exported backups include task content and event history. Keep them private.
- The Mac agent bridge accepts the same operating-system user through a Unix socket. It does not expose a network API. A connected local process can read and modify all App tasks; there is no per-project or per-agent access control.
- If an external agent sends task text to a model provider, that transfer is controlled by that tool and its configuration, not by Life · OS. Review its access before connecting it.
- Trashing is recoverable. Emptying trash prevents the removed records from reappearing in the current projection, but does not physically erase all event history or previous backups.
- Never attach real task databases, private notes, provisioning profiles, keys, or complete environment dumps to public reports.

For a suspected vulnerability, use GitHub's private vulnerability reporting when available. Otherwise open an Issue requesting a private reporting channel without including exploit details or private data.
