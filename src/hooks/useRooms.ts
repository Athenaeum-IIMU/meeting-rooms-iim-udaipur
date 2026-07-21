import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

// Rooms are effectively static — cache them for the whole session so we don't
// hit the DB on every mount/focus.
export const useRooms = () => {
  return useQuery({
    queryKey: ["rooms"],
    queryFn: async () => {
      const { data, error } = await supabase.from("rooms").select("*").order("name");
      if (error) throw error;
      return data;
    },
    staleTime: 60 * 60 * 1000, // 1 hour
    gcTime: 24 * 60 * 60 * 1000,
    refetchOnWindowFocus: false,
    refetchOnMount: false,
  });
};
