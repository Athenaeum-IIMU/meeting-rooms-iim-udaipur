import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useAuth } from "@/contexts/AuthContext";
import { useRooms } from "@/hooks/useRooms";
import { useCreateBooking } from "@/hooks/useBookings";
import { supabase } from "@/integrations/supabase/client";
import { Badge } from "@/components/ui/badge";
import { X, MapPin, Users, Info, AlertTriangle } from "lucide-react";

interface BookingModalProps {
  open: boolean;
  onClose: () => void;
  defaultDate?: string;
  defaultTime?: string;
  defaultEndTime?: string;
  defaultRoomId?: string;
}

const BookingModal = ({ open, onClose, defaultDate, defaultTime, defaultEndTime, defaultRoomId }: BookingModalProps) => {
  const { user, isAdmin } = useAuth();
  const { data: rooms } = useRooms();
  const createBooking = useCreateBooking();

  const today = new Date();
  const maxDate = new Date(today);
  maxDate.setDate(maxDate.getDate() + 1);

  const [title, setTitle] = useState("");
  const [roomId, setRoomId] = useState(defaultRoomId || "");
  const [date, setDate] = useState(defaultDate || today.toISOString().split("T")[0]);
  const [startTime, setStartTime] = useState(defaultTime || "09:00");
  const [endTime, setEndTime] = useState(defaultEndTime || (defaultTime ? addHour(defaultTime) : "10:00"));
  const [memberEmail, setMemberEmail] = useState("");
  const [members, setMembers] = useState<string[]>([]);
  const [conflictReason, setConflictReason] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);

  // Sync defaults whenever the modal is opened from a calendar slot
  useEffect(() => {
    if (!open) return;
    if (defaultRoomId) setRoomId(defaultRoomId);
    if (defaultDate) setDate(defaultDate);
    if (defaultTime) {
      setStartTime(defaultTime);
      setEndTime(defaultEndTime || addHour(defaultTime));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, defaultRoomId, defaultDate, defaultTime, defaultEndTime]);

  const selectedRoom = rooms?.find((r) => r.id === roomId);
  const minMembers = selectedRoom?.min_members || 3;

  const addMember = () => {
    const email = memberEmail.trim().toLowerCase();
    if (!email) return;
    if (!email.endsWith("@iimu.ac.in")) {
      setConflictReason("Only @iimu.ac.in email addresses can be invited.");
      return;
    }
    if (!members.includes(email) && email !== user?.email?.toLowerCase()) {
      setMembers([...members, email]);
      setMemberEmail("");
    }
  };

  const removeMember = (email: string) => {
    setMembers(members.filter((m) => m !== email));
  };

  const logAttempt = async (errorMessage: string) => {
    try {
      await supabase.rpc("log_booking_attempt", {
        p_room_id: roomId || "00000000-0000-0000-0000-000000000000",
        p_title: title || "(no title)",
        p_date: date,
        p_start_time: startTime,
        p_end_time: endTime,
        p_member_emails: members,
        p_error_message: errorMessage,
      });
    } catch {
      // best-effort logging; never block the UX
    }
  };

  const fail = async (reason: string) => {
    setConflictReason(reason);
    setChecking(false);
    await logAttempt(reason);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;

    // +1 for the booker themselves
    const totalMembers = members.length + 1;
    if (totalMembers < minMembers) {
      await logAttempt(
        `Not enough members: ${totalMembers}/${minMembers} required for ${selectedRoom?.name ?? "room"}`
      );
      return;
    }

    // Client-only sanity checks. Conflict / overlap / daily-limit / blocked-slot
    // checks are enforced server-side by triggers; their error messages bubble
    // up via the mutation's onError toast (and are logged by create_booking_logged).
    setChecking(true);
    if (endTime <= startTime) {
      await fail("End time must be after start time.");
      return;
    }
    const durMin = toMinLocal(endTime) - toMinLocal(startTime);
    // End-of-day exception: allow <30 min when it ends exactly at 23:59
    if (durMin < 30 && endTime !== "23:59") {
      await fail("A booking must be at least 30 minutes long (except end-of-day slots ending at 23:59).");
      return;
    }
    if (durMin > 120) {
      await fail("A single booking can be at most 2 hours long.");
      return;
    }
    const startDateTime = new Date(`${date}T${startTime}`);
    if (startDateTime.getTime() < Date.now()) {
      await fail("You cannot book a time that is already in the past.");
      return;
    }
    setChecking(false);

    // Ensure every invited member already has a profile (has signed in once).
    // Admins are exempt.
    if (!isAdmin && members.length > 0) {
      const { data: missing, error: profErr } = await supabase.rpc(
        "filter_unregistered_emails",
        { p_emails: members }
      );
      if (profErr) {
        await fail(profErr.message);
        return;
      }
      if (missing && missing.length > 0) {
        await fail(
          `These people haven't signed in to the platform yet:\n\n${missing.join("\n")}\n\nAsk them to log in at least once, then invite them again.`
        );
        return;
      }
    }

    try {
      await createBooking.mutateAsync({
        room_id: roomId,
        title,
        date,
        start_time: startTime,
        end_time: endTime,
        user_id: user.id,
        members,
      });
      onClose();
      resetForm();
    } catch (err) {
      // create_booking_logged already records the failed attempt server-side.
      // Surface the reason in a blocking dialog the user must acknowledge.
      let message = (err as Error)?.message || "Something went wrong. Please try again.";
      if (message.startsWith("NOT_REGISTERED:")) {
        const emails = message.slice("NOT_REGISTERED:".length).split(",").filter(Boolean);
        message = `These people haven't signed in yet, so they can't be invited:\n\n${emails.join("\n")}\n\nAsk them to log in once, then invite them again.`;
      }
      setConflictReason(message);
    }
  };

  const resetForm = () => {
    setTitle("");
    setRoomId("");
    setDate(today.toISOString().split("T")[0]);
    setStartTime("09:00");
    setEndTime("10:00");
    setMembers([]);
    setMemberEmail("");
  };

  const totalMembers = members.length + 1;

  return (
    <>
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Book a Room</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label>Meeting Title</Label>
            <Input value={title} onChange={(e) => setTitle(e.target.value)} required placeholder="Team standup" />
          </div>

          <div className="space-y-2">
            <Label>Room</Label>
            <Select value={roomId} onValueChange={setRoomId} required>
              <SelectTrigger><SelectValue placeholder="Select a room" /></SelectTrigger>
              <SelectContent>
                {rooms?.map((room) => (
                  <SelectItem key={room.id} value={room.id}>
                    {room.name} (Cap: {room.capacity}, Min: {room.min_members})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {selectedRoom && (
              <div className="rounded-md border bg-muted/40 p-2.5 text-xs space-y-1">
                <div className="flex flex-wrap gap-x-3 gap-y-1 text-muted-foreground">
                  {selectedRoom.location && (
                    <span className="flex items-center gap-1">
                      <MapPin className="h-3 w-3" /> {selectedRoom.location}
                    </span>
                  )}
                  <span className="flex items-center gap-1">
                    <Users className="h-3 w-3" /> Capacity {selectedRoom.capacity} • Min {selectedRoom.min_members}
                  </span>
                </div>
                {selectedRoom.description && (
                  <p className="flex items-start gap-1 text-foreground/80">
                    <Info className="mt-0.5 h-3 w-3 shrink-0 text-muted-foreground" />
                    <span>{selectedRoom.description}</span>
                  </p>
                )}
              </div>
            )}
          </div>

          <div className="space-y-2">
            <Label>Date</Label>
            <Input
              type="date"
              value={date}
              onChange={(e) => setDate(e.target.value)}
              min={today.toISOString().split("T")[0]}
              max={maxDate.toISOString().split("T")[0]}
              required
            />
            <p className="text-xs text-muted-foreground">Max 1 day in advance (today or tomorrow)</p>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Start Time</Label>
              <Input type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} required />
            </div>
            <div className="space-y-2">
              <Label>End Time</Label>
              <Input type="time" value={endTime} onChange={(e) => setEndTime(e.target.value)} required />
            </div>
            <p className="col-span-2 text-xs text-muted-foreground">
              Duration must be between 30 min and 2 hr. You can book up to 4 hr/day combined across all rooms.
            </p>
          </div>

          <div className="space-y-2">
            <Label>Add Members (min {minMembers} total incl. you)</Label>
            <div className="flex gap-2">
              <Input
                type="email"
                value={memberEmail}
                onChange={(e) => setMemberEmail(e.target.value)}
                placeholder="member@iimu.ac.in"
                onKeyDown={(e) => e.key === "Enter" && (e.preventDefault(), addMember())}
              />
              <Button type="button" variant="secondary" onClick={addMember}>Add</Button>
            </div>
            {members.length > 0 && (
              <div className="flex flex-wrap gap-1 mt-2">
                {members.map((email) => (
                  <Badge key={email} variant="secondary" className="gap-1">
                    {email}
                    <button type="button" onClick={() => removeMember(email)}>
                      <X className="h-3 w-3" />
                    </button>
                  </Badge>
                ))}
              </div>
            )}
            <p className="text-xs text-muted-foreground">
              Total members: {totalMembers}/{minMembers} required
              {totalMembers < minMembers && (
                <span className="text-destructive ml-1">
                  (need {minMembers - totalMembers} more)
                </span>
              )}
            </p>
          </div>

          <Button
            type="submit"
            className="w-full"
            disabled={createBooking.isPending || checking || totalMembers < minMembers || !roomId}
          >
            {checking
              ? "Checking availability…"
              : createBooking.isPending
              ? "Creating..."
              : "Create Booking"}
          </Button>
        </form>
      </DialogContent>
    </Dialog>

    <Dialog open={!!conflictReason}>
      <DialogContent
        className="sm:max-w-md border-destructive/40"
        hideCloseButton
        onInteractOutside={(e) => e.preventDefault()}
        onEscapeKeyDown={(e) => e.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 text-destructive">
            <AlertTriangle className="h-5 w-5" />
            Booking failed
          </DialogTitle>
        </DialogHeader>
        <div className="rounded-md border border-destructive/30 bg-destructive/5 p-3">
          <p className="whitespace-pre-line break-words text-sm text-foreground">{conflictReason}</p>
        </div>
        <p className="text-xs text-muted-foreground">
          Please fix the issue above before trying to book again.
        </p>
        <DialogFooter>
          <Button variant="destructive" onClick={() => setConflictReason(null)}>
            Got it, let me fix it
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
    </>
  );
};

function toMinLocal(t: string): number {
  const [h, m] = t.split(":").map(Number);
  return h * 60 + m;
}

function addHour(time: string): string {
  const [h, m] = time.split(":").map(Number);
  return `${String(Math.min(h + 1, 23)).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

export default BookingModal;
