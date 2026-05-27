import { useEffect } from "react";
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
      // Uses an anonymized SECURITY DEFINER RPC so users only see busy
      // time/room info for other people's bookings (not their titles/owners).
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
 * Subscribes to live changes on bookings, blocked_slots, and booking_members
 * so the calendar and "My Bookings" views update without a manual refresh.
 */
export const useBookingsRealtime = () => {
  const queryClient = useQueryClient();
  useEffect(() => {
    const channel = supabase
      .channel("realtime-bookings")
      .on("postgres_changes", { event: "*", schema: "public", table: "bookings" }, () => {
        queryClient.invalidateQueries({ queryKey: ["bookings"] });
        queryClient.invalidateQueries({ queryKey: ["my-bookings"] });
        queryClient.invalidateQueries({ queryKey: ["member-bookings"] });
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "blocked_slots" }, () => {
        queryClient.invalidateQueries({ queryKey: ["blocked_slots"] });
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "booking_members" }, () => {
        queryClient.invalidateQueries({ queryKey: ["pending-invites"] });
        queryClient.invalidateQueries({ queryKey: ["member-bookings"] });
        queryClient.invalidateQueries({ queryKey: ["my-bookings"] });
        queryClient.invalidateQueries({ queryKey: ["bookings"] });
      })
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
