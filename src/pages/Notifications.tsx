import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Bell, Check, Trash2 } from "lucide-react";
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

  const unreadCount = notifications?.filter((n) => !n.read).length || 0;

  const openNotif = (n: { id: string; read: boolean; booking_id: string | null }) => {
    if (!n.read) markRead.mutate(n.id);
    const target = isAdmin ? "/admin" : "/my-bookings";
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

      {!isLoading && (!notifications || notifications.length === 0) && (
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-12 text-muted-foreground">
            <Bell className="h-8 w-8" />
            <p className="text-sm">No notifications yet.</p>
            <p className="text-xs">You'll see updates about your bookings here.</p>
          </CardContent>
        </Card>
      )}

      <div className="space-y-2">
        {notifications?.map((n) => (
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