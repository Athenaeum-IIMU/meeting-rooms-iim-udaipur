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
      // All validation (blocked slots, conflicts, per-user overlaps, daily
      // 4-hour limit, 2-hour cap, past-date guard) is enforced server-side
      // by triggers on the bookings table. We rely on those error messages.
      const { data: bookingData, error } = await supabase
        .from("bookings")
        .insert({
          room_id: booking.room_id,
          title: booking.title,
          date: booking.date,
          start_time: booking.start_time,
          end_time: booking.end_time,
          user_id: booking.user_id,
          status: booking.members.length > 0 ? "pending_members" : "pending_admin",
        })
        .select()
        .single();
      if (error) throw error;

      // Insert members
      if (booking.members.length > 0) {
        const memberInserts = booking.members.map((email) => ({
          booking_id: bookingData.id,
          email: email.trim().toLowerCase(),
        }));
        const { error: memberError } = await supabase
          .from("booking_members")
          .insert(memberInserts);
        if (memberError) {
          // Clean up the orphan booking so the slot is free again
          await supabase.from("bookings").delete().eq("id", bookingData.id);
          throw new Error(memberError.message);
        }
      }

      return bookingData;
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
