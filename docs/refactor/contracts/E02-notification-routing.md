# In-app notification routing

The Home Needs action views expose aggregate alerts from existing report data. Open the existing report with the same filter that produced the alert. Ordinary report entry points retain their current defaults.

| Alert | Destination |
|---|---|
| Dues older than 30 days | Receivables filtered to the 31–60 and older buckets |
| Expired stock or stock expiring in the next seven days | Expiring stock report with seven-day window |
| Android sync problem | Existing sync status sheet |
| Android backup reminder | Existing backup sheet with normal restore behavior |

Use existing report access rules and current shop/account scope. Reject stale alerts after a scope change and hide results from any requests that finish under a previous scope. Opening an alert does not change business data. Verify the filters, empty/error states, scope switch, and normal report defaults in the browser and on Android.
