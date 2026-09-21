## Block multiple rooms at once

### What will change
- Keep the existing single blocked-slot editing flow.
- When creating blocks, allow admins to add multiple rows in one form.
- Each row will independently select a room, date, start time, end time, and reason.
- Validate every row before saving, then create all valid blocked slots together.
- Refresh the calendar and blocked-slot list once after completion, with a clear success or error message.

### Technical details
- Extend the existing blocked-slot dialog with repeatable entries and add/remove controls.
- Submit new entries through the existing protected blocked-slots access rules.
- Preserve existing conflict and cancellation behavior for every created block.
