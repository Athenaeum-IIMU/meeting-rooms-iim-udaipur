import { useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useRooms } from "@/hooks/useRooms";
import { useToast } from "@/hooks/use-toast";
import { useAuth } from "@/contexts/AuthContext";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Info } from "lucide-react";

interface EditBookingModalProps {
  open: boolean;
  onClose: () => void;
  booking: any | null;
}

const EditBookingModal = ({ open, onClose, booking }: EditBookingModalProps) => {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const { data: rooms } = useRooms();
  const { user } = useAuth();

  const today = new Date();
  const maxDate = new Date(today);
  maxDate.setDate(maxDate.getDate() + 1);

  const [title, setTitle] = useState("");
  const [roomId, setRoomId] = useState("");
  const [date, setDate] = useState("");
  const [startTime, setStartTime] = useState("");
  const [endTime, setEndTime] = useState("");

  useEffect(() => {
    if (booking) {
      setTitle(booking.title);
      setRoomId(booking.room_id);
      setDate(booking.date);
      setStartTime(booking.start_time.slice(0, 5));
      setEndTime(booking.end_time.slice(0, 5));
    }
  }, [booking]);

  const save = useMutation({
    mutationFn: async () => {
      if (!booking || !user) throw new Error("No booking");

      // Past time guard
      if (new Date(`${date}T${startTime}`).getTime() < Date.now()) {
        throw new Error("You cannot move a booking to a time in the past.");
      }

      // Per-booking duration: 30 min ≤ d ≤ 2 hr
      const toMin = (t: string) => {
        const [h, m] = t.split(":").map(Number);
        return h * 60 + m;
      };
      const dur = toMin(endTime) - toMin(startTime);
      if (dur <= 0) {
        throw new Error("End time must be after start time.");
      }
      if (dur < 30 && endTime !== "23:59") {
        throw new Error("A booking must be at least 30 minutes long (except end-of-day slots ending at 23:59).");
      }
      if (dur > 120) {
        throw new Error("A single booking can be at most 2 hours long.");
      }

      // Conflict / blocked-slot / overlap / 4hr-cap checks are enforced
      // server-side by triggers on the bookings table.
      const { error } = await supabase
        .from("bookings")
        .update({ title, room_id: roomId, date, start_time: startTime, end_time: endTime })
        .eq("id", booking.id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["my-bookings"] });
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast({
        title: "Booking updated",
        description: "It's been sent back to admin for approval.",
      });
      onClose();
    },
    onError: (e: Error) =>
      toast({ title: "Couldn't update", description: e.message, variant: "destructive" }),
  });

  if (!booking) return null;

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Edit Booking</DialogTitle>
        </DialogHeader>
        <Alert>
          <Info className="h-4 w-4" />
          <AlertDescription className="text-xs">
            Editing an approved booking will reset it to <strong>Awaiting Approval</strong> until an admin re-approves.
          </AlertDescription>
        </Alert>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            save.mutate();
          }}
          className="space-y-4"
        >
          <div className="space-y-2">
            <Label>Title</Label>
            <Input value={title} onChange={(e) => setTitle(e.target.value)} required />
          </div>

          <div className="space-y-2">
            <Label>Room</Label>
            <Select value={roomId} onValueChange={setRoomId} required>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {rooms?.map((r) => (
                  <SelectItem key={r.id} value={r.id}>{r.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
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
              <Label>Start</Label>
              <Input type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} required />
            </div>
            <div className="space-y-2">
              <Label>End</Label>
              <Input type="time" value={endTime} onChange={(e) => setEndTime(e.target.value)} required />
            </div>
            <p className="col-span-2 text-xs text-muted-foreground">
              Duration must be between 30 min and 2 hr. Daily limit is 4 hr per person across all rooms.
            </p>
          </div>

          <div className="flex gap-2">
            <Button type="button" variant="outline" onClick={onClose} className="flex-1">Cancel</Button>
            <Button type="submit" disabled={save.isPending} className="flex-1">
              {save.isPending ? "Saving…" : "Save & Resubmit"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
};

export default EditBookingModal;