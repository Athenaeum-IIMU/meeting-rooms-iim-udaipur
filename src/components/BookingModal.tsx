import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useAuth } from "@/contexts/AuthContext";
import { useRooms } from "@/hooks/useRooms";
import { useCreateBooking } from "@/hooks/useBookings";
import { Badge } from "@/components/ui/badge";
import { X, MapPin, Users, Info } from "lucide-react";

interface BookingModalProps {
  open: boolean;
  onClose: () => void;
  defaultDate?: string;
  defaultTime?: string;
  defaultRoomId?: string;
}

const BookingModal = ({ open, onClose, defaultDate, defaultTime, defaultRoomId }: BookingModalProps) => {
  const { user } = useAuth();
  const { data: rooms } = useRooms();
  const createBooking = useCreateBooking();

  const today = new Date();
  const maxDate = new Date(today);
  maxDate.setDate(maxDate.getDate() + 2);

  const [title, setTitle] = useState("");
  const [roomId, setRoomId] = useState(defaultRoomId || "");
  const [date, setDate] = useState(defaultDate || today.toISOString().split("T")[0]);
  const [startTime, setStartTime] = useState(defaultTime || "09:00");
  const [endTime, setEndTime] = useState(defaultTime ? addHour(defaultTime) : "10:00");
  const [memberEmail, setMemberEmail] = useState("");
  const [members, setMembers] = useState<string[]>([]);

  const selectedRoom = rooms?.find((r) => r.id === roomId);
  const minMembers = selectedRoom?.min_members || 3;

  const addMember = () => {
    const email = memberEmail.trim().toLowerCase();
    if (email && !members.includes(email) && email !== user?.email) {
      setMembers([...members, email]);
      setMemberEmail("");
    }
  };

  const removeMember = (email: string) => {
    setMembers(members.filter((m) => m !== email));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;

    // +1 for the booker themselves
    const totalMembers = members.length + 1;
    if (totalMembers < minMembers) {
      return;
    }

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
            <p className="text-xs text-muted-foreground">Max 2 days in advance</p>
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
            disabled={createBooking.isPending || totalMembers < minMembers || !roomId}
          >
            {createBooking.isPending ? "Creating..." : "Create Booking"}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
};

function addHour(time: string): string {
  const [h, m] = time.split(":").map(Number);
  return `${String(Math.min(h + 1, 23)).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

export default BookingModal;
