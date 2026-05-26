import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useToast } from "@/hooks/use-toast";
import { CalendarDays, Clock, MapPin, Users, Trash2, Pencil, History, Hourglass, Inbox, UserPlus, AlertTriangle } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import EditBookingModal from "@/components/EditBookingModal";
import { useMyWaitlist, useRemoveWaitlist } from "@/hooks/useWaitlist";
import { useBookingsRealtime } from "@/hooks/useBookings";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";

const statusBadge: Record<string, { variant: "default" | "secondary" | "destructive" | "outline"; label: string }> = {
  pending_members: { variant: "outline", label: "Awaiting Members" },
  pending_admin: { variant: "secondary", label: "Awaiting Approval" },
  approved: { variant: "default", label: "Approved" },
  rejected: { variant: "destructive", label: "Rejected" },
  cancelled: { variant: "outline", label: "Cancelled" },
  needs_replacement: { variant: "destructive", label: "Needs Replacement" },
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
  const [replacing, setReplacing] = useState<any | null>(null);
  const [replacementEmail, setReplacementEmail] = useState("");
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
    mutationFn: async ({ memberId, status }: { memberId: string; bookingId: string; status: string }) => {
      const { error } = await supabase.rpc("accept_booking_invite_atomic", {
        p_member_id: memberId,
        p_accept: status === "accepted",
      });
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["pending-invites"] });
      queryClient.invalidateQueries({ queryKey: ["my-bookings"] });
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast({ title: "Response recorded" });
    },
    onError: (e: Error) => {
      toast({
        title: "Couldn't accept invite",
        description: e.message,
        variant: "destructive",
      });
    },
  });

  const addReplacement = useMutation({
    mutationFn: async ({ bookingId, email }: { bookingId: string; email: string }) => {
      const clean = email.trim().toLowerCase();
      if (!clean) throw new Error("Enter an email");
      if (clean === (profile?.email || user?.email)?.toLowerCase()) {
        throw new Error("You're already the organizer");
      }
      const { error: insertError } = await supabase
        .from("booking_members")
        .insert({ booking_id: bookingId, email: clean });
      if (insertError) throw insertError;
      // Flip booking back to pending_members so the new invite is awaited
      await supabase
        .from("bookings")
        .update({ status: "pending_members" })
        .eq("id", bookingId);
    },
    onSuccess: () => {
      setReplacementEmail("");
      queryClient.invalidateQueries({ queryKey: ["my-bookings"] });
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast({ title: "Invitation sent", description: "Waiting for them to accept." });
    },
    onError: (e: Error) => {
      toast({ title: "Couldn't add member", description: e.message, variant: "destructive" });
    },
  });

  const activeBookings = (myBookings || []).filter(
    (b) => !["cancelled", "rejected"].includes(b.status) && b.date >= today
  );
  const needsReplacementBookings = (myBookings || []).filter(
    (b) => b.status === "needs_replacement" && b.date >= today
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

  // Fetch organizer profiles for participant bookings so we can display them as a member
  const organizerIds = useMemo(
    () => Array.from(new Set(participantBookings.map((b: any) => b.user_id).filter(Boolean))),
    [participantBookings]
  );
  const { data: organizerProfiles } = useQuery({
    queryKey: ["participant-organizers", organizerIds],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("profiles")
        .select("user_id, full_name, email")
        .in("user_id", organizerIds);
      if (error) throw error;
      return data;
    },
    enabled: organizerIds.length > 0,
  });
  const organizersById = useMemo(
    () => new Map((organizerProfiles || []).map((o) => [o.user_id, o])),
    [organizerProfiles]
  );

  const renderBookingCard = (booking: any, allowEdit: boolean) => {
    const badge = statusBadge[booking.status] || { variant: "outline" as const, label: booking.status };
    const isHighlighted = booking.id === highlightId;
    const members = (booking.booking_members as any[]) || [];
    const isOrganizer = booking.user_id === user?.id;
    const organizer = isOrganizer
      ? { email: profile?.email || user?.email, full_name: profile?.full_name }
      : organizersById.get(booking.user_id);
    const totalPeople = members.length + 1; // organizer counts too
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
                  <Users className="h-3 w-3" /> {totalPeople} {totalPeople === 1 ? "person" : "people"}
                </span>
              </div>
              {booking.status === "rejected" && booking.rejection_reason && (
                <p className="mt-1 rounded-md border border-destructive/30 bg-destructive/5 p-2 text-xs text-destructive">
                  <span className="font-semibold">Rejection reason:</span> {booking.rejection_reason}
                </p>
              )}
              <div className="mt-1 flex flex-wrap gap-1">
                {organizer?.email && (
                  <Badge variant="secondary" className="text-xs">
                    {organizer.email} (organizer)
                  </Badge>
                )}
                {members.map((m: any) => (
                  <Badge key={m.id} variant="outline" className="text-xs">
                    {m.email} ({m.status})
                  </Badge>
                ))}
              </div>
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
      {/* Bookings that need replacement members */}
      {needsReplacementBookings.length > 0 && (
        <div className="space-y-3">
          <h2 className="flex items-center gap-2 text-lg font-bold text-destructive">
            <AlertTriangle className="h-4 w-4" /> Action needed
          </h2>
          {needsReplacementBookings.map((booking: any) => {
            const declined = ((booking.booking_members as any[]) || []).filter((m) => m.status === "rejected");
            const room = (booking.rooms as any);
            return (
              <Card key={booking.id} className="border-destructive/50">
                <CardContent className="space-y-3 p-4">
                  <div className="space-y-1">
                    <p className="font-semibold">{booking.title}</p>
                    <p className="text-sm text-muted-foreground">
                      {room?.name} • {booking.date} • {booking.start_time.slice(0, 5)}–{booking.end_time.slice(0, 5)}
                    </p>
                    <p className="text-sm text-destructive">
                      {declined.length > 0
                        ? `${declined.map((m: any) => m.email).join(", ")} declined.`
                        : "Not enough members accepted."}{" "}
                      Add a replacement or cancel — auto-cancel applies 30 min before start.
                    </p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <Button size="sm" variant="outline" onClick={() => { setReplacing(booking); setReplacementEmail(""); }}>
                      <UserPlus className="mr-1 h-3 w-3" /> Add replacement
                    </Button>
                    <Button size="sm" variant="destructive" onClick={() => cancelBooking.mutate(booking.id)}>
                      Cancel booking
                    </Button>
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}

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

      <Dialog open={!!replacing} onOpenChange={(o) => !o && setReplacing(null)}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Add replacement member</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            Invite someone to fill the spot for "{replacing?.title}".
          </p>
          <Input
            type="email"
            placeholder="member@iimu.ac.in"
            value={replacementEmail}
            onChange={(e) => setReplacementEmail(e.target.value)}
          />
          <DialogFooter>
            <Button variant="outline" onClick={() => setReplacing(null)}>Close</Button>
            <Button
              disabled={addReplacement.isPending || !replacementEmail.trim()}
              onClick={() => addReplacement.mutate({ bookingId: replacing.id, email: replacementEmail })}
            >
              {addReplacement.isPending ? "Sending…" : "Send invite"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default MyBookings;
