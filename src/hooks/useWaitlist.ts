import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { useToast } from "@/hooks/use-toast";

export const useMyWaitlist = () => {
  const { user } = useAuth();
  return useQuery({
    queryKey: ["waitlist", user?.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("waitlist")
        .select("*, rooms(name)")
        .eq("user_id", user!.id)
        .order("date", { ascending: true });
      if (error) throw error;
      return data;
    },
    enabled: !!user,
  });
};

export const useRemoveWaitlist = () => {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from("waitlist").delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["waitlist"] });
      toast({ title: "Removed from waitlist" });
    },
  });
};