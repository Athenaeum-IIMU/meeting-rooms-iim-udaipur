import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useToast } from "@/hooks/use-toast";
import { useEffect } from "react";

// Polling interval: 10 minutes. Realtime subscriptions (below) push instant
// updates, so polling is only a safety net — a longer interval slashes idle
// DB reads and Cloud usage without affecting UX.
const POLL_INTERVAL = 10 * 60 * 1000;

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
 * Lightweight realtime: subscribe to bookings + blocked_slots changes and
 * invalidate the calendar caches so edits show up immediately. Polling
 * remains as a safety net (every 3 minutes).
 */
export const useBookingsRealtime = () => {
  const queryClient = useQueryClient();
  useEffect(() => {
    const channel = supabase
      .channel("calendar-changes")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "bookings" },
        () => {
          queryClient.invalidateQueries({ queryKey: ["bookings"] });
        }
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "blocked_slots" },
        () => {
          queryClient.invalidateQueries({ queryKey: ["blocked_slots"] });
        }
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [queryClient]);
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
      const { data, error } = await supabase.rpc("create_booking_logged", {
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
      let description = error.message;
      if (description.startsWith("NOT_REGISTERED:")) {
        const emails = description.slice("NOT_REGISTERED:".length).split(",").filter(Boolean);
        description = `These people haven't signed in yet, so they can't be invited:\n${emails.join("\n")}\nAsk them to log in once, then invite them again.`;
      }
      toast({ title: "Booking failed", description, variant: "destructive" });
    },
  });
};
