import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { useToast } from "@/hooks/use-toast";
import { CalendarDays, Clock, MapPin, Users, Trash2 } from "lucide-react";

const statusBadge: Record<string, { variant: "default" | "secondary" | "destructive" | "outline"; label: string }> = {
  pending_members: { variant: "outline", label: "Awaiting Members" },
  pending_admin: { variant: "secondary", label: "Awaiting Approval" },
  approved: { variant: "default", label: "Approved" },
  rejected: { variant: "destructive", label: "Rejected" },
  cancelled: { variant: "outline", label: "Cancelled" },
};

const MyBookings = () => {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const { toast } = useToast();

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
    queryKey: ["pending-invites", profile?.email],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("booking_members")
        .select("*, bookings(*, rooms(name), profiles!bookings_user_id_fkey(full_name, email))")
        .eq("email", profile!.email)
        .eq("status", "pending");
      if (error) throw error;
      return data;
    },
    enabled: !!profile?.email,
  });

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

  return (
    <div className="space-y-6">
      {/* Pending Invites */}
      {pendingInvites && pendingInvites.length > 0 && (
        <div className="space-y-3">
          <h2 className="text-lg font-bold">Pending Invitations</h2>
          {pendingInvites.map((invite) => (
            <Card key={invite.id} className="border-orange-400/50">
              <CardContent className="flex items-center justify-between p-4">
                <div>
                  <p className="font-medium">{(invite.bookings as any)?.title}</p>
                  <p className="text-sm text-muted-foreground">
                    {(invite.bookings as any)?.rooms?.name} •{" "}
                    {(invite.bookings as any)?.date} •{" "}
                    {(invite.bookings as any)?.start_time?.slice(0, 5)}–{(invite.bookings as any)?.end_time?.slice(0, 5)}
                  </p>
                  <p className="text-xs text-muted-foreground">
                    By: {(invite.bookings as any)?.profiles?.full_name || (invite.bookings as any)?.profiles?.email}
                  </p>
                </div>
                <div className="flex gap-2">
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
          ))}
        </div>
      )}

      {/* My Bookings */}
      <div className="space-y-3">
        <h2 className="text-lg font-bold">My Bookings</h2>
        {myBookings?.length === 0 && (
          <p className="text-sm text-muted-foreground">No bookings yet. Go to Calendar to book a room!</p>
        )}
        {myBookings?.map((booking) => {
          const badge = statusBadge[booking.status] || { variant: "outline" as const, label: booking.status };
          return (
            <Card key={booking.id}>
              <CardContent className="p-4">
                <div className="flex items-start justify-between">
                  <div className="space-y-1">
                    <div className="flex items-center gap-2">
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
                      <div className="flex flex-wrap gap-1 mt-1">
                        {(booking.booking_members as any[]).map((m: any) => (
                          <Badge key={m.id} variant="outline" className="text-xs">
                            {m.email} ({m.status})
                          </Badge>
                        ))}
                      </div>
                    )}
                  </div>
                  {!["cancelled", "rejected"].includes(booking.status) && (
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => cancelBooking.mutate(booking.id)}
                      title="Cancel booking"
                    >
                      <Trash2 className="h-4 w-4 text-destructive" />
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          );
        })}
      </div>
    </div>
  );
};

export default MyBookings;
