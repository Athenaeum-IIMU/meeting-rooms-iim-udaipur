## Meeting Room Scheduler — IIM Udaipur

### Overview

A calendar-based meeting room booking system with user authentication, conflict detection, and admin approval workflow.

### Pages & Layout

1. **Login/Signup** — Email + password auth via Supabase
2. **Calendar View (Home)** — Weekly/daily calendar grid showing all rooms and bookings
3. **My Bookings** — List of user's bookings with status (pending/approved/rejected)
4. **Admin Panel** — Approve/reject pending booking requests (admin-only)

### Database (Supabase)

- **profiles** — id, user_id, full_name, email
- **user_roles** — id, user_id, role (admin/user)
- **rooms** — id, name, capacity, location, description (pre-populated with IIM Udaipur rooms)
- **bookings** — id, room_id, user_id, title, date, start_time, end_time, status (pending/approved/rejected), created_at

### Key Features

- **Calendar Grid** — Weekly view with time slots (12 AM–11:59 PM), rooms as columns. Color-coded by status (pending = yellow, approved = green, rejected = red)
- **Book a Room** — Click a time slot → modal with room, date, start/end time, meeting title. Conflict detection prevents overlapping approved bookings
- **Admin Approval** — Admins see pending requests and can approve/reject with one click
- **RLS Policies** — Users see all approved bookings, only their own pending/rejected. Admins see everything
- **Responsive** — Works on desktop and mobile
- 1 email id or 1 person cannot use any meeting room for more than 4 hours combined
- meeting room MR1 has to have 2 members minimum to book and all other meeting rooms has to have more than 3 members to book
- send a confirmation mail to the other members mentioned in the booking and they have to accept that and only then it has to come for admin approval to get the slot booked for that group and incase in the mean time another group has come and all their members have accepted the mail then it should be visible for admin permission at the top and then the other group permission should be seen after they accept it
- admin can have access to modify or block certain slots and then automatically others cant book in that times and incase someone has already booked in those times send a mail to the whole group saying the meeting room slot has been cancelled
- 1 person cannot be booking in 2 rooms in the same time or in time that they are using other room
- to the admin , requests approval must be visible in the order that who ever fills first must be displayed at top
- max date and time that 1 can book in advance is only 2 days any booking that they need for above 2 days in advance would not be possible to start off with

### Room List

I'll add placeholder rooms (Board Room, Conference Room 1-3, Seminar Hall, etc.) — you can update the names after seeing the app. Please share the actual room names if you'd like them pre-populated.

meeting rooms list: MR-1, Rumi, Chanakya, Frida