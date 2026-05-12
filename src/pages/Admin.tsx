import { useEffect, useMemo, useRef, useState } from "react";
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
import { Textarea } from "@/components/ui/textarea";
import { useRooms } from "@/hooks/useRooms";
import { useBookingsRealtime } from "@/hooks/useBookings";
import { useToast } from "@/hooks/use-toast";
import { Check, X, Shield, Ban, CalendarDays, Clock, MapPin, Users, Pencil } from "lucide-react";
import AdminEditBookingModal from "@/components/AdminEditBookingModal";
import AdminRoomsTab from "@/components/AdminRoomsTab";
import AdminUsersTab from "@/components/AdminUsersTab";
import { ScrollText, Building2, UserCog } from "lucide-react";
import { formatDistanceToNow } from "date-fns";

const Admin = () => {
  const { user, isAdmin } = useAuth();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const { data: rooms } = useRooms();
  useBookingsRealtime();
  const [blockModalOpen, setBlockModalOpen] = useState(false);
  const [editingBooking, setEditingBooking] = useState<any | null>(null);
  const [rejectingBooking, setRejectingBooking] = useState<any | null>(null);
  const [rejectReason, setRejectReason] = useState("");
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
        .select("*, rooms(name), booking_members(*)")
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
        .select("*, rooms(name), booking_members(*)")
        .order("created_at", { ascending: false })
        .limit(50);
      if (error) throw error;
      return data;
    },
    enabled: isAdmin,
  });

  // Fetch profiles for booking owners separately (FK points to auth.users, so embed isn't possible)
  const ownerIds = useMemo(() => {
    const ids = new Set<string>();
    (pendingBookings || []).forEach((b: any) => b.user_id && ids.add(b.user_id));
    (allBookings || []).forEach((b: any) => b.user_id && ids.add(b.user_id));
    return Array.from(ids);
  }, [pendingBookings, allBookings]);

  const { data: ownerProfiles } = useQuery({
    queryKey: ["admin-owner-profiles", ownerIds],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("profiles")
        .select("user_id, full_name, email")
        .in("user_id", ownerIds);
      if (error) throw error;
      return data;
    },
    enabled: isAdmin && ownerIds.length > 0,
  });

  const ownerById = useMemo(
    () => new Map((ownerProfiles || []).map((p) => [p.user_id, p])),
    [ownerProfiles]
  );

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
    mutationFn: async ({ bookingId, reason }: { bookingId: string; reason: string }) => {
      const { error } = await supabase
        .from("bookings")
        .update({ status: "rejected", rejection_reason: reason || null })
        .eq("id", bookingId);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["admin-pending"] });
      queryClient.invalidateQueries({ queryKey: ["admin-all-bookings"] });
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast({ title: "Booking rejected", description: "Members have been notified." });
      setRejectingBooking(null);
      setRejectReason("");
    },
    onError: (e: Error) => {
      toast({ title: "Reject failed", description: e.message, variant: "destructive" });
    },
  });

  const openRejectDialog = (booking: any) => {
    const room = (booking.rooms as any)?.name || "the room";
    const time = `${booking.start_time.slice(0, 5)}–${booking.end_time.slice(0, 5)}`;
    setRejectReason(
      `Your booking "${booking.title}" in ${room} on ${booking.date} (${time}) could not be approved due to a scheduling conflict or room policy. Please pick a different slot or room and try again.`
    );
    setRejectingBooking(booking);
  };

  const approveAllPending = useMutation({
    mutationFn: async (ids: string[]) => {
      const { error } = await supabase
        .from("bookings")
        .update({ status: "approved" })
        .in("id", ids);
      if (error) throw error;
      return ids.length;
    },
    onSuccess: (count) => {
      queryClient.invalidateQueries({ queryKey: ["admin-pending"] });
      queryClient.invalidateQueries({ queryKey: ["admin-all-bookings"] });
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast({ title: `Approved ${count} bookings` });
    },
    onError: (e: Error) => toast({ title: "Bulk approve failed", description: e.message, variant: "destructive" }),
  });

  // Filters for the All Bookings tab
  const [filterStatus, setFilterStatus] = useState<string>("all");
  const [filterDate, setFilterDate] = useState<string>("");

  const filteredBookings = (allBookings || []).filter((b) => {
    if (filterStatus !== "all" && b.status !== filterStatus) return false;
    if (filterDate && b.date !== filterDate) return false;
    return true;
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
          <TabsTrigger value="rooms" className="gap-1">
            <Building2 className="h-3 w-3" /> Rooms
          </TabsTrigger>
          <TabsTrigger value="users" className="gap-1">
            <UserCog className="h-3 w-3" /> Users
          </TabsTrigger>
          <TabsTrigger value="audit">
            <ScrollText className="mr-1 h-3 w-3" /> Audit Log
          </TabsTrigger>
        </TabsList>

        <TabsContent value="pending" className="space-y-3 mt-4">
          {pendingBookings && pendingBookings.length > 0 && (
            <div className="flex justify-end">
              <Button
                size="sm"
                variant="outline"
                onClick={() => approveAllPending.mutate(pendingBookings.map((b) => b.id))}
                disabled={approveAllPending.isPending}
                className="gap-1"
              >
                <Check className="h-3 w-3" /> Approve all ({pendingBookings.length})
              </Button>
            </div>
          )}
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
                      By: {ownerById.get(booking.user_id)?.full_name || ownerById.get(booking.user_id)?.email || "—"}
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
                      onClick={() => openRejectDialog(booking)}
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
          <div className="flex flex-wrap items-end gap-3 rounded-md border p-3">
            <div className="space-y-1">
              <Label className="text-xs">Status</Label>
              <Select value={filterStatus} onValueChange={setFilterStatus}>
                <SelectTrigger className="h-8 w-44">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All statuses</SelectItem>
                  <SelectItem value="pending_members">Awaiting members</SelectItem>
                  <SelectItem value="pending_admin">Awaiting approval</SelectItem>
                  <SelectItem value="approved">Approved</SelectItem>
                  <SelectItem value="rejected">Rejected</SelectItem>
                  <SelectItem value="cancelled">Cancelled</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Date</Label>
              <Input
                type="date"
                value={filterDate}
                onChange={(e) => setFilterDate(e.target.value)}
                className="h-8 w-44"
              />
            </div>
            {(filterStatus !== "all" || filterDate) && (
              <Button
                size="sm"
                variant="ghost"
                onClick={() => {
                  setFilterStatus("all");
                  setFilterDate("");
                }}
              >
                Clear
              </Button>
            )}
            <span className="ml-auto text-xs text-muted-foreground">
              {filteredBookings.length} of {allBookings?.length || 0}
            </span>
          </div>
          {filteredBookings.length === 0 && (
            <p className="text-sm text-muted-foreground">No bookings match these filters.</p>
          )}
          {filteredBookings.map((booking) => {
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
                      by {ownerById.get(booking.user_id)?.full_name || ownerById.get(booking.user_id)?.email || "—"}
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

        <TabsContent value="rooms" className="mt-4">
          <AdminRoomsTab />
        </TabsContent>

        <TabsContent value="users" className="mt-4">
          <AdminUsersTab />
        </TabsContent>

        <TabsContent value="audit" className="space-y-2 mt-4">
          {!auditLog || auditLog.length === 0 ? (
            <p className="text-sm text-muted-foreground">No admin actions recorded yet.</p>
          ) : (
            auditLog.map((entry) => (
              <Card key={entry.id}>
                <CardContent className="flex items-start justify-between p-3 text-sm">
                  <div className="min-w-0 flex-1">
                    <p className="font-medium">{entry.summary}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">
                      by {entry.actor_email || "system"} •{" "}
                      {formatDistanceToNow(new Date(entry.created_at), { addSuffix: true })}
                    </p>
                  </div>
                  <Badge variant="outline" className="ml-2 shrink-0 text-xs">
                    {entry.action}
                  </Badge>
                </CardContent>
              </Card>
            ))
          )}
        </TabsContent>
      </Tabs>

      <AdminEditBookingModal
        open={!!editingBooking}
        onClose={() => setEditingBooking(null)}
        booking={editingBooking}
      />

      <Dialog
        open={!!rejectingBooking}
        onOpenChange={(o) => {
          if (!o) {
            setRejectingBooking(null);
            setRejectReason("");
          }
        }}
      >
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Reject booking</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <p className="text-sm text-muted-foreground">
              The organizer and accepted members will receive this reason in their notifications. Edit it before sending.
            </p>
            <Textarea
              value={rejectReason}
              onChange={(e) => setRejectReason(e.target.value)}
              rows={5}
              placeholder="Why is this booking being rejected?"
            />
            <div className="flex gap-2">
              <Button
                variant="outline"
                className="flex-1"
                onClick={() => {
                  setRejectingBooking(null);
                  setRejectReason("");
                }}
              >
                Cancel
              </Button>
              <Button
                variant="destructive"
                className="flex-1"
                disabled={!rejectReason.trim() || rejectBooking.isPending}
                onClick={() =>
                  rejectBooking.mutate({
                    bookingId: rejectingBooking.id,
                    reason: rejectReason.trim(),
                  })
                }
              >
                {rejectBooking.isPending ? "Sending…" : "Reject & notify"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
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
