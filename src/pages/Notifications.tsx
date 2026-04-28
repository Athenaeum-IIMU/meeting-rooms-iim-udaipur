import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Bell, Check, Trash2, Search } from "lucide-react";
import { useMemo, useState } from "react";
import {
  useNotifications,
  useMarkNotificationRead,
  useMarkAllNotificationsRead,
  useDeleteNotification,
} from "@/hooks/useNotifications";
import { formatDistanceToNow } from "date-fns";
import { useNavigate } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";

const Notifications = () => {
  const { data: notifications, isLoading } = useNotifications();
  const markRead = useMarkNotificationRead();
  const markAllRead = useMarkAllNotificationsRead();
  const deleteNotif = useDeleteNotification();
  const navigate = useNavigate();
  const { isAdmin } = useAuth();
  const [search, setSearch] = useState("");
  const [typeFilter, setTypeFilter] = useState<string>("all");

  const types = useMemo(() => {
    const s = new Set<string>();
    notifications?.forEach((n) => s.add(n.type));
    return Array.from(s).sort();
  }, [notifications]);

  const filtered = useMemo(() => {
    return (notifications || []).filter((n) => {
      if (typeFilter !== "all" && n.type !== typeFilter) return false;
      if (search) {
        const q = search.toLowerCase();
        if (
          !n.title.toLowerCase().includes(q) &&
          !n.body.toLowerCase().includes(q)
        )
          return false;
      }
      return true;
    });
  }, [notifications, search, typeFilter]);

  const unreadCount = notifications?.filter((n) => !n.read).length || 0;

  const openNotif = (n: { id: string; read: boolean; booking_id: string | null; type: string }) => {
    if (!n.read) markRead.mutate(n.id);
    const personalTypes = ["invite", "member_accepted", "member_rejected", "booking_approved", "booking_rejected", "booking_cancelled", "booking_modified", "waitlist_available"];
    const target = personalTypes.includes(n.type) || !isAdmin ? "/my-bookings" : "/admin";
    navigate(n.booking_id ? `${target}?booking=${n.booking_id}` : target);
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Notifications</h1>
        {unreadCount > 0 && (
          <Button variant="outline" size="sm" onClick={() => markAllRead.mutate()}>
            Mark all read ({unreadCount})
          </Button>
        )}
      </div>

      {isLoading && <p className="text-sm text-muted-foreground">Loading...</p>}

      {notifications && notifications.length > 0 && (
        <div className="flex flex-wrap items-center gap-2 rounded-md border p-2">
          <div className="relative flex-1 min-w-[180px]">
            <Search className="absolute left-2 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search notifications…"
              className="h-8 pl-7"
            />
          </div>
          <Select value={typeFilter} onValueChange={setTypeFilter}>
            <SelectTrigger className="h-8 w-44">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All types</SelectItem>
              {types.map((t) => (
                <SelectItem key={t} value={t}>
                  {t.replace(/_/g, " ")}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          {(search || typeFilter !== "all") && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setSearch("");
                setTypeFilter("all");
              }}
            >
              Clear
            </Button>
          )}
          <span className="ml-auto text-xs text-muted-foreground">
            {filtered.length} of {notifications.length}
          </span>
        </div>
      )}

      {!isLoading && (!notifications || notifications.length === 0) && (
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-12 text-muted-foreground">
            <Bell className="h-8 w-8" />
            <p className="text-sm">No notifications yet.</p>
            <p className="text-xs">You'll see updates about your bookings here.</p>
          </CardContent>
        </Card>
      )}

      {!isLoading && notifications && notifications.length > 0 && filtered.length === 0 && (
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-10 text-muted-foreground">
            <Search className="h-6 w-6" />
            <p className="text-sm">No notifications match these filters.</p>
          </CardContent>
        </Card>
      )}

      <div className="space-y-2">
        {filtered.map((n) => (
          <Card
            key={n.id}
            onClick={() => openNotif(n)}
            className={`cursor-pointer transition hover:shadow-md ${
              !n.read ? "border-primary/40 bg-primary/5" : ""
            }`}
          >
            <CardContent className="flex items-start gap-3 p-4">
              {!n.read && (
                <Badge variant="default" className="mt-1 h-2 w-2 shrink-0 rounded-full p-0" />
              )}
              <div className="min-w-0 flex-1">
                <p className="font-medium">{n.title}</p>
                <p className="mt-0.5 text-sm text-muted-foreground">{n.body}</p>
                <p className="mt-1 text-xs text-muted-foreground/70">
                  {formatDistanceToNow(new Date(n.created_at), { addSuffix: true })}
                </p>
              </div>
              <div className="flex gap-1">
                {!n.read && (
                  <Button
                    variant="ghost"
                    size="icon"
                    onClick={(e) => {
                      e.stopPropagation();
                      markRead.mutate(n.id);
                    }}
                    title="Mark read"
                  >
                    <Check className="h-4 w-4" />
                  </Button>
                )}
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={(e) => {
                    e.stopPropagation();
                    deleteNotif.mutate(n.id);
                  }}
                  title="Delete"
                >
                  <Trash2 className="h-4 w-4 text-destructive" />
                </Button>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
};

export default Notifications;