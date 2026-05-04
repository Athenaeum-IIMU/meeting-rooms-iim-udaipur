import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useToast } from "@/hooks/use-toast";
import { CalendarDays, Clock, MapPin, Users, Trash2, Pencil, History, Hourglass, Inbox } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import EditBookingModal from "@/components/EditBookingModal";
import { useMyWaitlist, useRemoveWaitlist } from "@/hooks/useWaitlist";
import { useBookingsRealtime } from "@/hooks/useBookings";

const statusBadge: Record<string, { variant: "default" | "secondary" | "destructive" | "outline"; label: string }> = {
  pending_members: { variant: "outline", label: "Awaiting Members" },
  pending_admin: { variant: "secondary", label: "Awaiting Approval" },
  approved: { variant: "default", label: "Approved" },
  rejected: { variant: "destructive", label: "Rejected" },
  cancelled: { variant: "outline", label: "Cancelled" },
};

const MyBookings = () => {
  const { user, profile } = useAuth();
  useBookingsRealtime();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const [searchParams] = useSearchParams();
  const highlightId = searchParams.get("booking");
  const highlightRef = useRef<HTMLDivElement | null>(null);
  const inviteHighlightRef = useRef<HTMLDivElement | null>(null);
  const [editing, setEditing] = useState<any | null>(null);
  const [tab, setTab] = useState("active");
  const today = new Date().toISOString().split("T")[0];

  useEffect(() => {
    if (!highlightId) return;
    const target = inviteHighlightRef.current || highlightRef.current;
    if (target) {
      target.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  });

  // Bookings I created
  const { data: myBookings } = useQuery({
    queryKey: ["my-bookings", user?.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("bookings")
        .select("*, rooms(name, location), booking_members(*)")
        .eq("user_id", user!.id)
        .order("created_at", { ascending: false });
      if (error) throw error;
      return data;
    },
    enabled: !!user,
  });

  // Bookings where I'm a member (pending acceptance)
  const { data: pendingInvites } = useQuery({
    queryKey: ["pending-invites", user?.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("booking_members")
        .select("*, bookings(*, rooms(name, location))")
        .eq("user_id", user!.id)
        .eq("status", "pending");
      if (error) throw error;
      return data;
    },
    enabled: !!user?.id,
  });

  // Bookings where I'm an accepted member (show in My Bookings as participant)
  const { data: memberBookings } = useQuery({
    queryKey: ["member-bookings", user?.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("booking_members")
        .select("*, bookings(*, rooms(name, location), booking_members(*))")
        .eq("user_id", user!.id)
        .eq("status", "accepted");
      if (error) throw error;
      return data;
    },
    enabled: !!user?.id,
  });

  const inviteOwnerIds = useMemo(
    () => Array.from(new Set((pendingInvites || []).map((invite: any) => invite.bookings?.user_id).filter(Boolean))),
    [pendingInvites]
  );

  const { data: inviteOwners } = useQuery({
    queryKey: ["pending-invite-owners", inviteOwnerIds],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("profiles")
        .select("user_id, full_name, email")
        .in("user_id", inviteOwnerIds);
      if (error) throw error;
      return data;
    },
    enabled: inviteOwnerIds.length > 0,
  });

  const inviteOwnersById = useMemo(
    () => new Map((inviteOwners || []).map((owner) => [owner.user_id, owner])),
    [inviteOwners]
  );

  const { data: waitlist } = useMyWaitlist();
  const removeWaitlist = useRemoveWaitlist();

  const cancelBooking = useMutation({
    mutationFn: async (bookingId: string) => {
      const { error } = await supabase
        .from("bookings")
        .update({ status: "cancelled" })
        .eq("id", bookingId);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["my-bookings"] });
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast({ title: "Booking cancelled" });
    },
  });

  const respondToInvite = useMutation({
    mutationFn: async ({ memberId, bookingId, status }: { memberId: string; bookingId: string; status: string }) => {
      const { error } = await supabase
        .from("booking_members")
        .update({ status, user_id: user!.id })
        .eq("id", memberId);
      if (error) throw error;

      // Check if all members accepted → move to pending_admin
      if (status === "accepted") {
        const { data: allMembers } = await supabase
          .from("booking_members")
          .select("status")
          .eq("booking_id", bookingId);
        const allAccepted = allMembers?.every((m) => m.status === "accepted");
        if (allAccepted) {
          await supabase
            .from("bookings")
            .update({ status: "pending_admin" })
            .eq("id", bookingId);
        }
      }

      if (status === "rejected") {
        // If any member rejects, cancel the booking
        await supabase
          .from("bookings")
          .update({ status: "cancelled" })
          .eq("id", bookingId);
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["pending-invites"] });
      queryClient.invalidateQueries({ queryKey: ["my-bookings"] });
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast({ title: "Response recorded" });
    },
  });

  const activeBookings = (myBookings || []).filter(
    (b) => !["cancelled", "rejected"].includes(b.status) && b.date >= today
  );
  const pastBookings = (myBookings || []).filter(
    (b) => ["cancelled", "rejected"].includes(b.status) || b.date < today
  );

  // Meetings I'm a participant in (not the organizer)
  const participantBookings = (memberBookings || [])
    .map((m: any) => m.bookings)
    .filter((b: any) => b && b.user_id !== user?.id);
  const activeParticipant = participantBookings.filter(
    (b: any) => !["cancelled", "rejected"].includes(b.status) && b.date >= today
  );
  const pastParticipant = participantBookings.filter(
    (b: any) => ["cancelled", "rejected"].includes(b.status) || b.date < today
  );

  const renderBookingCard = (booking: any, allowEdit: boolean) => {
    const badge = statusBadge[booking.status] || { variant: "outline" as const, label: booking.status };
    const isHighlighted = booking.id === highlightId;
    return (
      <Card
        key={booking.id}
        ref={isHighlighted ? highlightRef : undefined}
        className={
          isHighlighted ? "ring-2 ring-primary ring-offset-2 transition-all" : ""
        }
      >
        <CardContent className="p-4">
          <div className="flex items-start justify-between gap-2">
            <div className="space-y-1">
              <div className="flex flex-wrap items-center gap-2">
                <h3 className="font-semibold">{booking.title}</h3>
                <Badge variant={badge.variant}>{badge.label}</Badge>
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
                <span className="flex items-center gap-1">
                  <Users className="h-3 w-3" /> {(booking.booking_members as any[])?.length || 0} members
                </span>
              </div>
              {(booking.booking_members as any[])?.length > 0 && (
                <div className="mt-1 flex flex-wrap gap-1">
                  {(booking.booking_members as any[]).map((m: any) => (
                    <Badge key={m.id} variant="outline" className="text-xs">
                      {m.email} ({m.status})
                    </Badge>
                  ))}
                </div>
              )}
            </div>
            {allowEdit && (
              <div className="flex shrink-0 gap-1">
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => setEditing(booking)}
                  title="Edit (will need re-approval)"
                >
                  <Pencil className="h-4 w-4" />
                </Button>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => cancelBooking.mutate(booking.id)}
                  title="Cancel booking"
                >
                  <Trash2 className="h-4 w-4 text-destructive" />
                </Button>
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    );
  };

  return (
    <div className="space-y-6">
      {/* Pending Invites */}
      {pendingInvites && pendingInvites.length > 0 && (
        <div className="space-y-3">
          <h2 className="text-lg font-bold">Pending Invitations</h2>
          {pendingInvites.map((invite) => {
            const isHighlighted = invite.booking_id === highlightId;
            const owner = inviteOwnersById.get((invite.bookings as any)?.user_id);
            return (
              <div key={invite.id} ref={isHighlighted ? inviteHighlightRef : undefined}>
                <Card className={`border-orange-400/50 ${isHighlighted ? "ring-2 ring-primary ring-offset-2 transition-all" : ""}`}>
                  <CardContent className="flex flex-col gap-4 p-4 md:flex-row md:items-center md:justify-between">
                    <div className="space-y-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="font-medium">{(invite.bookings as any)?.title}</p>
                        <Badge variant="outline">Invitation pending</Badge>
                      </div>
                      <p className="text-sm text-muted-foreground">
                        {(invite.bookings as any)?.rooms?.name} • {(invite.bookings as any)?.date} • {(invite.bookings as any)?.start_time?.slice(0, 5)}–{(invite.bookings as any)?.end_time?.slice(0, 5)}
                      </p>
                      {(invite.bookings as any)?.rooms?.location && (
                        <p className="text-xs text-muted-foreground">Location: {(invite.bookings as any)?.rooms?.location}</p>
                      )}
                      <p className="text-xs text-muted-foreground">
                        By: {owner?.full_name || owner?.email || "Meeting organizer"}
                      </p>
                    </div>
                    <div className="flex flex-wrap gap-2">
                      <Button
                        size="sm"
                        onClick={() =>
                          respondToInvite.mutate({
                            memberId: invite.id,
                            bookingId: invite.booking_id,
                            status: "accepted",
                          })
                        }
                      >
                        Accept
                      </Button>
                      <Button
                        size="sm"
                        variant="destructive"
                        onClick={() =>
                          respondToInvite.mutate({
                            memberId: invite.id,
                            bookingId: invite.booking_id,
                            status: "rejected",
                          })
                        }
                      >
                        Decline
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              </div>
            );
          })}
        </div>
      )}

      {/* Waitlist */}
      {waitlist && waitlist.length > 0 && (
        <div className="space-y-3">
          <h2 className="flex items-center gap-2 text-lg font-bold">
            <Hourglass className="h-4 w-4" /> On Your Waitlist
          </h2>
          {waitlist.map((w) => (
            <Card key={w.id}>
              <CardContent className="flex items-center justify-between p-3">
                <div className="text-sm">
                  <span className="font-medium">{(w.rooms as any)?.name}</span>{" "}
                  <span className="text-muted-foreground">
                    • {w.date} • {w.start_time.slice(0, 5)}–{w.end_time.slice(0, 5)}
                  </span>
                  <p className="text-xs text-muted-foreground">
                    You'll be notified if this slot frees up.
                  </p>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => removeWaitlist.mutate(w.id)}
                  title="Remove from waitlist"
                >
                  <Trash2 className="h-4 w-4 text-destructive" />
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {/* My Bookings tabs */}
      <div className="space-y-3">
        <Tabs value={tab} onValueChange={setTab}>
          <TabsList>
            <TabsTrigger value="active">
              Active {activeBookings.length ? `(${activeBookings.length})` : ""}
            </TabsTrigger>
            <TabsTrigger value="past" className="gap-1">
              <History className="h-3 w-3" /> History
              {pastBookings.length ? ` (${pastBookings.length})` : ""}
            </TabsTrigger>
          </TabsList>
          <TabsContent value="active" className="mt-4 space-y-3">
            {activeBookings.length === 0 && activeParticipant.length === 0 ? (
              <Card>
                <CardContent className="flex flex-col items-center gap-2 py-10 text-muted-foreground">
                  <Inbox className="h-8 w-8" />
                  <p className="text-sm">No active bookings.</p>
                  <p className="text-xs">Head to the Calendar to book a room.</p>
                </CardContent>
              </Card>
            ) : (
              <>
                {activeBookings.map((b) => renderBookingCard(b, true))}
                {activeParticipant.length > 0 && (
                  <>
                    <h3 className="pt-2 text-sm font-semibold text-muted-foreground">Meetings you're part of</h3>
                    {activeParticipant.map((b: any) => renderBookingCard(b, false))}
                  </>
                )}
              </>
            )}
          </TabsContent>
          <TabsContent value="past" className="mt-4 space-y-3">
            {pastBookings.length === 0 && pastParticipant.length === 0 ? (
              <Card>
                <CardContent className="flex flex-col items-center gap-2 py-10 text-muted-foreground">
                  <History className="h-8 w-8" />
                  <p className="text-sm">No past bookings yet.</p>
                </CardContent>
              </Card>
            ) : (
              <>
                {pastBookings.map((b) => renderBookingCard(b, false))}
                {pastParticipant.map((b: any) => renderBookingCard(b, false))}
              </>
            )}
          </TabsContent>
        </Tabs>
      </div>

      <EditBookingModal
        open={!!editing}
        onClose={() => setEditing(null)}
        booking={editing}
      />
    </div>
  );
};

export default MyBookings;
