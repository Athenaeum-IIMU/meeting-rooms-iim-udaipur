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
  });
};

/**
 * Subscribe to realtime updates on bookings, members, and blocked slots.
 * Invalidates relevant queries so calendar / admin / my-bookings refresh live.
 */
export const useBookingsRealtime = () => {
  const queryClient = useQueryClient();
  useEffect(() => {
    const channel = supabase
      .channel("bookings-realtime")
      .on("postgres_changes", { event: "*", schema: "public", table: "bookings" }, () => {
        queryClient.invalidateQueries({ queryKey: ["bookings"] });
        queryClient.invalidateQueries({ queryKey: ["my-bookings"] });
        queryClient.invalidateQueries({ queryKey: ["member-bookings"] });
        queryClient.invalidateQueries({ queryKey: ["admin-pending"] });
        queryClient.invalidateQueries({ queryKey: ["admin-all-bookings"] });
        queryClient.invalidateQueries({ queryKey: ["pending-invites"] });
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "blocked_slots" }, () => {
        queryClient.invalidateQueries({ queryKey: ["blocked_slots"] });
        queryClient.invalidateQueries({ queryKey: ["admin-blocked-slots"] });
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
      // Check blocked slot
      const { data: isBlocked } = await supabase.rpc("check_blocked_slot", {
        p_room_id: booking.room_id,
        p_date: booking.date,
        p_start_time: booking.start_time,
        p_end_time: booking.end_time,
      });
      if (isBlocked) throw new Error("This time slot is blocked by admin.");

      // Check conflict
      const { data: hasConflict } = await supabase.rpc("check_booking_conflict", {
        p_room_id: booking.room_id,
        p_date: booking.date,
        p_start_time: booking.start_time,
        p_end_time: booking.end_time,
      });
      if (hasConflict) throw new Error("Time slot conflicts with an existing booking.");

      // Check user time overlap
      const { data: hasOverlap } = await supabase.rpc("check_user_time_overlap", {
        p_user_id: booking.user_id,
        p_date: booking.date,
        p_start_time: booking.start_time,
        p_end_time: booking.end_time,
      });
      if (hasOverlap) throw new Error("You already have a booking during this time.");

      // Check daily hours
      const { data: dailyHours } = await supabase.rpc("get_user_daily_hours", {
        p_user_id: booking.user_id,
        p_date: booking.date,
      });
      const currentMinutes = parseInterval(dailyHours || "00:00:00");
      const newMinutes = timeToMinutes(booking.end_time) - timeToMinutes(booking.start_time);
      if (currentMinutes + newMinutes > 240) {
        throw new Error("You cannot book more than 4 hours total per day.");
      }

      // Insert booking
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

function parseInterval(interval: string): number {
  const parts = interval.split(":");
  return parseInt(parts[0]) * 60 + parseInt(parts[1]);
}

function timeToMinutes(time: string): number {
  const [h, m] = time.split(":").map(Number);
  return h * 60 + m;
}
