import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { useToast } from "@/hooks/use-toast";

export const useBookings = (date?: string) => {
  return useQuery({
    queryKey: ["bookings", date],
    queryFn: async () => {
      let query = supabase
        .from("bookings")
        .select("*, rooms(name), booking_members(*)");
      if (date) {
        query = query.eq("date", date);
      }
      const { data, error } = await query.order("created_at", { ascending: true });
      if (error) throw error;
      return data;
    },
    refetchInterval: 30000,
    refetchOnWindowFocus: true,
  });
};

export const useWeekBookings = (startDate: string, endDate: string) => {
  return useQuery({
    queryKey: ["bookings", "week", startDate, endDate],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("bookings")
        .select("*, rooms(name), booking_members(*)")
        .gte("date", startDate)
        .lte("date", endDate)
        .order("created_at", { ascending: true });
      if (error) throw error;
      return data;
    },
    refetchInterval: 30000,
    refetchOnWindowFocus: true,
  });
};

export const useBlockedSlots = (startDate: string, endDate: string) => {
  return useQuery({
    queryKey: ["blocked_slots", startDate, endDate],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("blocked_slots")
        .select("*, rooms(name)")
        .gte("date", startDate)
        .lte("date", endDate);
      if (error) throw error;
      return data;
    },
    refetchInterval: 30000,
    refetchOnWindowFocus: true,
  });
};

/**
 * No-op: bookings and blocked_slots are no longer broadcast over Realtime
 * (to avoid leaking row changes to all authenticated subscribers). Queries
 * poll via refetchInterval / window focus instead.
 */
export const useBookingsRealtime = () => {
  // Intentionally empty.
};

export const useCreateBooking = () => {
  const queryClient = useQueryClient();
  const { toast } = useToast();

  return useMutation({
    mutationFn: async (booking: {
      room_id: string;
      title: string;
      date: string;
      start_time: string;
      end_time: string;
      user_id: string;
      members: string[];
    }) => {
      // Atomic insert (booking + invitees) in a single DB transaction.
      // The server forces user_id = auth.uid() and enforces all validation.
      const { data, error } = await supabase.rpc("create_booking_atomic", {
        p_room_id: booking.room_id,
        p_title: booking.title,
        p_date: booking.date,
        p_start_time: booking.start_time,
        p_end_time: booking.end_time,
        p_member_emails: booking.members.map((e) => e.trim().toLowerCase()),
      });
      if (error) throw error;
      return { id: data as string };
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["bookings"] });
      toast({ title: "Booking created!", description: "Waiting for member confirmations." });
    },
    onError: (error: Error) => {
      toast({ title: "Booking failed", description: error.message, variant: "destructive" });
    },
  });
};
