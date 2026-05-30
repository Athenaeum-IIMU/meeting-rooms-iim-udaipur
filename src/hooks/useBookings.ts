import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useToast } from "@/hooks/use-toast";

// Polling interval: 3 minutes. We rely on polling (not realtime) to reduce
// Cloud usage. Manual mutations also invalidate queries for instant feedback.
const POLL_INTERVAL = 3 * 60 * 1000;

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
    refetchInterval: POLL_INTERVAL,
    refetchOnWindowFocus: true,
  });
};

export const useWeekBookings = (startDate: string, endDate: string) => {
  return useQuery({
    queryKey: ["bookings", "week", startDate, endDate],
    queryFn: async () => {
      const { data, error } = await supabase.rpc("get_calendar_busy_slots", {
        p_start_date: startDate,
        p_end_date: endDate,
      });
      if (error) throw error;
      return (data ?? []) as Array<{
        id: string;
        room_id: string;
        date: string;
        start_time: string;
        end_time: string;
        status: string;
        is_mine: boolean;
        title: string;
        user_id: string | null;
      }>;
    },
    refetchInterval: POLL_INTERVAL,
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
    refetchInterval: POLL_INTERVAL,
    refetchOnWindowFocus: true,
  });
};

/**
 * Realtime is intentionally disabled to reduce Cloud usage.
 * Data refreshes via polling (every 3 minutes) and on-mutation invalidation.
 * This no-op is kept so existing call sites compile unchanged.
 */
export const useBookingsRealtime = () => {
  // intentionally empty
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
