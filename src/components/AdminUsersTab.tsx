import { useMemo, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";
import { useAuth } from "@/contexts/AuthContext";
import { Search, Shield, ShieldOff } from "lucide-react";

const AdminUsersTab = () => {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const { user: currentUser } = useAuth();
  const [search, setSearch] = useState("");

  const { data: users } = useQuery({
    queryKey: ["admin-users"],
    queryFn: async () => {
      const [profilesRes, rolesRes] = await Promise.all([
        supabase.from("profiles").select("user_id, full_name, email").order("full_name"),
        supabase.from("user_roles").select("user_id, role"),
      ]);
      if (profilesRes.error) throw profilesRes.error;
      if (rolesRes.error) throw rolesRes.error;
      const adminIds = new Set(
        (rolesRes.data || []).filter((r) => r.role === "admin").map((r) => r.user_id)
      );
      return (profilesRes.data || []).map((p) => ({ ...p, isAdmin: adminIds.has(p.user_id) }));
    },
  });

  const filtered = useMemo(() => {
    if (!users) return [];
    if (!search) return users;
    const q = search.toLowerCase();
    return users.filter(
      (u) =>
        (u.full_name || "").toLowerCase().includes(q) ||
        (u.email || "").toLowerCase().includes(q)
    );
  }, [users, search]);

  const promote = useMutation({
    mutationFn: async (userId: string) => {
      const { error } = await supabase
        .from("user_roles")
        .insert({ user_id: userId, role: "admin" });
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["admin-users"] });
      toast({ title: "User promoted to admin" });
    },
    onError: (e: Error) =>
      toast({ title: "Couldn't promote", description: e.message, variant: "destructive" }),
  });

  const demote = useMutation({
    mutationFn: async (userId: string) => {
      const { error } = await supabase
        .from("user_roles")
        .delete()
        .eq("user_id", userId)
        .eq("role", "admin");
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["admin-users"] });
      toast({ title: "Admin role removed" });
    },
    onError: (e: Error) =>
      toast({ title: "Couldn't demote", description: e.message, variant: "destructive" }),
  });

  return (
    <div className="space-y-3">
      <div className="relative max-w-sm">
        <Search className="absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by name or email…"
          className="h-8 pl-7"
        />
      </div>

      {filtered.length === 0 && (
        <p className="text-sm text-muted-foreground">No users match.</p>
      )}

      {filtered.map((u) => {
        const isSelf = u.user_id === currentUser?.id;
        return (
          <Card key={u.user_id}>
            <CardContent className="flex items-center justify-between gap-3 p-3">
              <div className="min-w-0">
                <p className="font-medium">
                  {u.full_name || "(no name)"}
                  {isSelf && (
                    <span className="ml-1 text-xs text-muted-foreground">(you)</span>
                  )}
                </p>
                <p className="text-xs text-muted-foreground">{u.email}</p>
              </div>
              <div className="flex items-center gap-2">
                {u.isAdmin && (
                  <Badge className="gap-1">
                    <Shield className="h-3 w-3" /> Admin
                  </Badge>
                )}
                {u.isAdmin ? (
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={isSelf || demote.isPending}
                    onClick={() => demote.mutate(u.user_id)}
                    className="gap-1"
                    title={isSelf ? "You can't remove your own admin role" : "Remove admin"}
                  >
                    <ShieldOff className="h-3 w-3" /> Demote
                  </Button>
                ) : (
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={promote.isPending}
                    onClick={() => promote.mutate(u.user_id)}
                    className="gap-1"
                  >
                    <Shield className="h-3 w-3" /> Make admin
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
};

export default AdminUsersTab;