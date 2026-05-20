import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useRooms } from "@/hooks/useRooms";
import { useToast } from "@/hooks/use-toast";
import { X } from "lucide-react";

interface AdminEditBookingModalProps {
  open: boolean;
  onClose: () => void;
  booking: any | null;
}

const AdminEditBookingModal = ({ open, onClose, booking }: AdminEditBookingModalProps) => {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const { data: rooms } = useRooms();

  const [title, setTitle] = useState("");
  const [roomId, setRoomId] = useState("");
  const [date, setDate] = useState("");
  const [startTime, setStartTime] = useState("");
  const [endTime, setEndTime] = useState("");
  const [ownerId, setOwnerId] = useState("");
  const [memberEmail, setMemberEmail] = useState("");
  const [members, setMembers] = useState<string[]>([]);

  // All profiles for owner-reassignment dropdown
  const { data: profiles } = useQuery({
    queryKey: ["all-profiles"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("profiles")
        .select("user_id, full_name, email")
        .order("full_name", { ascending: true });
      if (error) throw error;
      return data;
    },
    enabled: open,
  });

  useEffect(() => {
    if (booking) {
      setTitle(booking.title);
      setRoomId(booking.room_id);
      setDate(booking.date);
      setStartTime(booking.start_time.slice(0, 5));
      setEndTime(booking.end_time.slice(0, 5));
      setOwnerId(booking.user_id);
      setMembers((booking.booking_members || []).map((m: any) => m.email));
      setMemberEmail("");
    }
  }, [booking]);

  const addMember = () => {
    const email = memberEmail.trim().toLowerCase();
    if (email && !members.includes(email)) {
      setMembers([...members, email]);
      setMemberEmail("");
    }
  };

  const removeMember = (email: string) => {
    setMembers(members.filter((m) => m !== email));
  };

  const saveBooking = useMutation({
    mutationFn: async () => {
      if (!booking) throw new Error("No booking selected");

      // Conflict check enforced server-side by trigger on bookings table.
      const { error: updateError } = await supabase
        .from("bookings")
        .update({
          title,
          room_id: roomId,
          date,
          start_time: startTime,
          end_time: endTime,
          user_id: ownerId,
        })
        .eq("id", booking.id);
      if (updateError) throw updateError;

      // Sync members: delete all and re-insert
      const { error: deleteError } = await supabase
        .from("booking_members")
        .delete()
        .eq("booking_id", booking.id);
      if (deleteError) throw deleteError;

      if (members.length > 0) {
        // Skip the new owner from being added as a "member"
        const ownerProfile = profiles?.find((p) => p.user_id === ownerId);
        const filteredMembers = members.filter(
          (m) => m.toLowerCase() !== ownerProfile?.email?.toLowerCase()
        );
        if (filteredMembers.length > 0) {
          const { error: insertError } = await supabase.from("booking_members").insert(
            filteredMembers.map((email) => ({
              booking_id: booking.id,
              email: email.trim().toLowerCase(),
              status: "accepted",
            }))
          );
          if (insertError) throw insertError;
        }
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["admin-pending"] });
      queryClient.invalidateQueries({ queryKey: ["admin-all-bookings"] });
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast({ title: "Booking updated" });
      onClose();
    },
    onError: (e: Error) => {
      toast({ title: "Update failed", description: e.message, variant: "destructive" });
    },
  });

  if (!booking) return null;

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Edit Booking (Admin)</DialogTitle>
        </DialogHeader>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            saveBooking.mutate();
          }}
          className="space-y-4"
        >
          <div className="space-y-2">
            <Label>Title</Label>
            <Input value={title} onChange={(e) => setTitle(e.target.value)} required />
          </div>

          <div className="space-y-2">
            <Label>Owner</Label>
            <Select value={ownerId} onValueChange={setOwnerId} required>
              <SelectTrigger>
                <SelectValue placeholder="Select owner" />
              </SelectTrigger>
              <SelectContent>
                {profiles?.map((p) => (
                  <SelectItem key={p.user_id} value={p.user_id}>
                    {p.full_name || p.email} ({p.email})
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label>Room</Label>
            <Select value={roomId} onValueChange={setRoomId} required>
              <SelectTrigger>
                <SelectValue placeholder="Select room" />
              </SelectTrigger>
              <SelectContent>
                {rooms?.map((r) => (
                  <SelectItem key={r.id} value={r.id}>
                    {r.name} (Cap: {r.capacity})
                  </SelectItem>
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
              required
            />
            <p className="text-xs text-muted-foreground">
              Admins can pick any date.
            </p>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label>Start Time</Label>
              <Input
                type="time"
                value={startTime}
                onChange={(e) => setStartTime(e.target.value)}
                required
              />
            </div>
            <div className="space-y-2">
              <Label>End Time</Label>
              <Input
                type="time"
                value={endTime}
                onChange={(e) => setEndTime(e.target.value)}
                required
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label>Members</Label>
            <div className="flex gap-2">
              <Input
                type="email"
                value={memberEmail}
                onChange={(e) => setMemberEmail(e.target.value)}
                placeholder="member@iimu.ac.in"
                onKeyDown={(e) => e.key === "Enter" && (e.preventDefault(), addMember())}
              />
              <Button type="button" variant="secondary" onClick={addMember}>
                Add
              </Button>
            </div>
            {members.length > 0 && (
              <div className="mt-2 flex flex-wrap gap-1">
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
              Admin-added members are auto-accepted (no invite required).
            </p>
          </div>

          <div className="flex gap-2">
            <Button type="button" variant="outline" onClick={onClose} className="flex-1">
              Cancel
            </Button>
            <Button type="submit" disabled={saveBooking.isPending} className="flex-1">
              {saveBooking.isPending ? "Saving..." : "Save Changes"}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
};

export default AdminEditBookingModal;