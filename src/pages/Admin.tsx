import { useEffect, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useRooms } from "@/hooks/useRooms";
import { useToast } from "@/hooks/use-toast";
import { Check, X, Shield, Ban, CalendarDays, Clock, MapPin, Users, Pencil } from "lucide-react";
import AdminEditBookingModal from "@/components/AdminEditBookingModal";
import { ScrollText } from "lucide-react";
import { formatDistanceToNow } from "date-fns";

const Admin = () => {
  const { user, isAdmin } = useAuth();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const { data: rooms } = useRooms();
  const [blockModalOpen, setBlockModalOpen] = useState(false);
  const [editingBooking, setEditingBooking] = useState<any | null>(null);
  const [searchParams] = useSearchParams();
  const highlightId = searchParams.get("booking");
  const highlightRef = useRef<HTMLDivElement | null>(null);
  const [activeTab, setActiveTab] = useState("pending");

  useEffect(() => {
    if (!highlightId) return;
    // Switch to "all" tab so the highlighted booking is reachable regardless of status
    setActiveTab("all");
    const t = setTimeout(() => {
      highlightRef.current?.scrollIntoView({ behavior: "smooth", block: "center" });
    }, 150);
    return () => clearTimeout(t);
  }, [highlightId]);

  // Pending admin bookings ordered by created_at (first come first serve)
  const { data: pendingBookings } = useQuery({
    queryKey: ["admin-pending"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("bookings")
        .select("*, rooms(name), profiles!bookings_user_id_fkey(full_name, email), booking_members(*)")
        .eq("status", "pending_admin")
        .order("created_at", { ascending: true });
      if (error) throw error;
      return data;
    },
    enabled: isAdmin,
  });

  // All bookings for overview
  const { data: allBookings } = useQuery({
    queryKey: ["admin-all-bookings"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("bookings")
        .select("*, rooms(name), profiles!bookings_user_id_fkey(full_name, email), booking_members(*)")
        .order("created_at", { ascending: false })
        .limit(50);
      if (error) throw error;
      return data;
    },
    enabled: isAdmin,
  });

  // Blocked slots
  const { data: blockedSlots } = useQuery({
    queryKey: ["admin-blocked-slots"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("blocked_slots")
        .select("*, rooms(name)")
        .order("date", { ascending: true });
      if (error) throw error;
      return data;
    },
    enabled: isAdmin,
  });

  // Audit log
  const { data: auditLog } = useQuery({
    queryKey: ["admin-audit-log"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("audit_log")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(200);
      if (error) throw error;
      return data;
    },
    enabled: isAdmin,
  });

  const approveBooking = useMutation({
    mutationFn: async (bookingId: string) => {
      const { error } = await supabase
        .from("bookings")
        .update({ status: "approved" })
        .eq("id", bookingId);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["admin-pending"] });
      queryClient.invalidateQueries({ queryKey: ["admin-all-bookings"] });
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast({ title: "Booking approved!" });
    },
  });

  const rejectBooking = useMutation({
    mutationFn: async (bookingId: string) => {
      const { error } = await supabase
        .from("bookings")
        .update({ status: "rejected" })
        .eq("id", bookingId);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["admin-pending"] });
      queryClient.invalidateQueries({ queryKey: ["admin-all-bookings"] });
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast({ title: "Booking rejected" });
    },
  });

  if (!isAdmin) {
    return (
      <div className="flex items-center justify-center py-20 text-muted-foreground">
        <Shield className="mr-2 h-5 w-5" /> Admin access required.
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Admin Panel</h1>

      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="pending">
            Pending Approvals {pendingBookings?.length ? `(${pendingBookings.length})` : ""}
          </TabsTrigger>
          <TabsTrigger value="all">All Bookings</TabsTrigger>
          <TabsTrigger value="blocked">Blocked Slots</TabsTrigger>
          <TabsTrigger value="audit">
            <ScrollText className="mr-1 h-3 w-3" /> Audit Log
          </TabsTrigger>
        </TabsList>

        <TabsContent value="pending" className="space-y-3 mt-4">
          {pendingBookings?.length === 0 && (
            <p className="text-sm text-muted-foreground">No pending approvals.</p>
          )}
          {pendingBookings?.map((booking, index) => {
            const isH = booking.id === highlightId;
            return (
            <Card
              key={booking.id}
              ref={isH ? highlightRef : undefined}
              className={isH ? "ring-2 ring-primary ring-offset-2" : ""}
            >
              <CardContent className="p-4">
                <div className="flex items-start justify-between">
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
                      <Badge variant="outline" className="text-xs">#{index + 1}</Badge>
                      <h3 className="font-semibold">{booking.title}</h3>
                    </div>
                    <div className="flex flex-wrap gap-3 text-sm text-muted-foreground">
                      <span className="flex items-center gap-1">
                        <MapPin className="h-3 w-3" /> {(booking.rooms as any)?.name}
                      </span>
                      <span className="flex items-center gap-1">
                        <CalendarDays className="h-3 w-3" /> {booking.date}
                      </span>
                      <span className="flex items-center gap-1">
                        <Clock className="h-3 w-3" /> {booking.start_time.slice(0, 5)}–{booking.end_time.slice(0, 5)}
                      </span>
                    </div>
                    <p className="text-xs text-muted-foreground">
                      By: {(booking.profiles as any)?.full_name || (booking.profiles as any)?.email}
                    </p>
                    {(booking.booking_members as any[])?.length > 0 && (
                      <div className="flex flex-wrap gap-1 mt-1">
                        <Users className="h-3 w-3 text-muted-foreground mt-0.5" />
                        {(booking.booking_members as any[]).map((m: any) => (
                          <Badge key={m.id} variant="secondary" className="text-xs">
                            {m.email} ✓
                          </Badge>
                        ))}
                      </div>
                    )}
                  </div>
                  <div className="flex gap-2">
                    <Button
                      size="sm"
                      onClick={() => approveBooking.mutate(booking.id)}
                      className="gap-1"
                    >
                      <Check className="h-3 w-3" /> Approve
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setEditingBooking(booking)}
                      className="gap-1"
                    >
                      <Pencil className="h-3 w-3" /> Edit
                    </Button>
                    <Button
                      size="sm"
                      variant="destructive"
                      onClick={() => rejectBooking.mutate(booking.id)}
                      className="gap-1"
                    >
                      <X className="h-3 w-3" /> Reject
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
            );
          })}
        </TabsContent>

        <TabsContent value="all" className="space-y-3 mt-4">
          {allBookings?.map((booking) => {
            const statusColor: Record<string, string> = {
              approved: "bg-green-100 text-green-800",
              pending_admin: "bg-yellow-100 text-yellow-800",
              pending_members: "bg-orange-100 text-orange-800",
              rejected: "bg-red-100 text-red-800",
              cancelled: "bg-gray-100 text-gray-800",
            };
            const isH = booking.id === highlightId;
            return (
              <Card
                key={booking.id}
                ref={isH ? highlightRef : undefined}
                className={isH ? "ring-2 ring-primary ring-offset-2" : ""}
              >
                <CardContent className="flex items-center justify-between p-3">
                  <div className="text-sm">
                    <span className="font-medium">{booking.title}</span>{" "}
                    <span className="text-muted-foreground">
                      • {(booking.rooms as any)?.name} • {booking.date} {booking.start_time.slice(0, 5)}–{booking.end_time.slice(0, 5)}
                    </span>
                    <span className="text-xs text-muted-foreground ml-2">
                      by {(booking.profiles as any)?.full_name || (booking.profiles as any)?.email}
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    <Badge className={statusColor[booking.status] || ""}>{booking.status}</Badge>
                    {!["cancelled", "rejected"].includes(booking.status) && (
                      <Button
                        size="sm"
                        variant="ghost"
                        onClick={() => setEditingBooking(booking)}
                        className="h-7 gap-1"
                      >
                        <Pencil className="h-3 w-3" /> Edit
                      </Button>
                    )}
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </TabsContent>

        <TabsContent value="blocked" className="space-y-3 mt-4">
          <Button onClick={() => setBlockModalOpen(true)} className="gap-1">
            <Ban className="h-4 w-4" /> Block a Slot
          </Button>

          {blockedSlots?.map((slot) => (
            <Card key={slot.id}>
              <CardContent className="flex items-center justify-between p-3">
                <div className="text-sm">
                  <span className="font-medium">{(slot.rooms as any)?.name}</span>{" "}
                  <span className="text-muted-foreground">
                    • {slot.date} • {slot.start_time.slice(0, 5)}–{slot.end_time.slice(0, 5)}
                  </span>
                  {slot.reason && <span className="text-xs text-muted-foreground ml-2">({slot.reason})</span>}
                </div>
              </CardContent>
            </Card>
          ))}

          <BlockSlotModal
            open={blockModalOpen}
            onClose={() => setBlockModalOpen(false)}
            rooms={rooms || []}
            userId={user!.id}
          />
        </TabsContent>
      </Tabs>

      <AdminEditBookingModal
        open={!!editingBooking}
        onClose={() => setEditingBooking(null)}
        booking={editingBooking}
      />
    </div>
  );
};

const BlockSlotModal = ({
  open,
  onClose,
  rooms,
  userId,
}: {
  open: boolean;
  onClose: () => void;
  rooms: any[];
  userId: string;
}) => {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const [roomId, setRoomId] = useState("");
  const [date, setDate] = useState("");
  const [startTime, setStartTime] = useState("09:00");
  const [endTime, setEndTime] = useState("17:00");
  const [reason, setReason] = useState("");

  const blockSlot = useMutation({
    mutationFn: async () => {
      // First block the slot
      const { error } = await supabase
        .from("blocked_slots")
        .insert({ room_id: roomId, date, start_time: startTime, end_time: endTime, reason, created_by: userId });
      if (error) throw error;

      // Cancel any existing bookings that overlap
      const { data: overlapping } = await supabase
        .from("bookings")
        .select("id")
        .eq("room_id", roomId)
        .eq("date", date)
        .in("status", ["pending_members", "pending_admin", "approved"])
        .lt("start_time", endTime)
        .gt("end_time", startTime);

      if (overlapping && overlapping.length > 0) {
        for (const booking of overlapping) {
          await supabase.from("bookings").update({ status: "cancelled" }).eq("id", booking.id);
        }
        toast({ title: `${overlapping.length} overlapping booking(s) cancelled.` });
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["admin-blocked-slots"] });
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      queryClient.invalidateQueries({ queryKey: ["blocked_slots"] });
      toast({ title: "Slot blocked successfully" });
      onClose();
    },
    onError: (e: Error) => {
      toast({ title: "Error", description: e.message, variant: "destructive" });
    },
  });

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Block a Time Slot</DialogTitle>
        </DialogHeader>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            blockSlot.mutate();
          }}
          className="space-y-4"
        >
          <div className="space-y-2">
            <Label>Room</Label>
            <Select value={roomId} onValueChange={setRoomId} required>
              <SelectTrigger><SelectValue placeholder="Select room" /></SelectTrigger>
              <SelectContent>
                {rooms.map((r) => (
                  <SelectItem key={r.id} value={r.id}>{r.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label>Date</Label>
            <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
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
          </div>
          <div className="space-y-2">
            <Label>Reason (optional)</Label>
            <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Maintenance, event, etc." />
          </div>
          <Button type="submit" className="w-full" disabled={blockSlot.isPending}>
            {blockSlot.isPending ? "Blocking..." : "Block Slot"}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
};

export default Admin;
