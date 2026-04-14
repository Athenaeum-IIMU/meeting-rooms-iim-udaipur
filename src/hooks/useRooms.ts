import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

export const useRooms = () => {
  return useQuery({
    queryKey: ["rooms"],
    queryFn: async () => {
      const { data, error } = await supabase.from("rooms").select("*").order("name");
      if (error) throw error;
      return data;
    },
  });
};
