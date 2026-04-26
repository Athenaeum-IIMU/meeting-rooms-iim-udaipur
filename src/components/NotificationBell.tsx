import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { Bell, Check, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  useNotifications,
  useMarkNotificationRead,
  useMarkAllNotificationsRead,
  useDeleteNotification,
} from "@/hooks/useNotifications";
import { formatDistanceToNow } from "date-fns";
import { useAuth } from "@/contexts/AuthContext";

const NotificationBell = () => {
  const [open, setOpen] = useState(false);
  const { data: notifications } = useNotifications();
  const markRead = useMarkNotificationRead();
  const markAllRead = useMarkAllNotificationsRead();
  const deleteNotif = useDeleteNotification();
  const navigate = useNavigate();
  const { isAdmin } = useAuth();

  const unreadCount = notifications?.filter((n) => !n.read).length || 0;

  const handleClick = (n: { id: string; read: boolean; booking_id: string | null }) => {
    if (!n.read) markRead.mutate(n.id);
    setOpen(false);
    const target = isAdmin ? "/admin" : "/my-bookings";
    navigate(n.booking_id ? `${target}?booking=${n.booking_id}` : target);
  };

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button variant="ghost" size="icon" className="relative" title="Notifications">
          <Bell className="h-4 w-4" />
          {unreadCount > 0 && (
            <Badge
              variant="destructive"
              className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full p-0 text-[10px]"
            >
              {unreadCount > 9 ? "9+" : unreadCount}
            </Badge>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-80 p-0">
        <div className="flex items-center justify-between border-b px-3 py-2">
          <span className="text-sm font-semibold">Notifications</span>
          {unreadCount > 0 && (
            <Button
              variant="ghost"
              size="sm"
              className="h-7 text-xs"
              onClick={() => markAllRead.mutate()}
            >
              Mark all read
            </Button>
          )}
        </div>
        <ScrollArea className="h-80">
          {!notifications || notifications.length === 0 ? (
            <p className="p-6 text-center text-sm text-muted-foreground">
              No notifications yet.
            </p>
          ) : (
            <ul className="divide-y">
              {notifications.slice(0, 15).map((n) => (
                <li
                  key={n.id}
                  onClick={() => handleClick(n)}
                  className={`group flex cursor-pointer gap-2 p-3 text-sm hover:bg-muted/50 ${
                    !n.read ? "bg-primary/5" : ""
                  }`}
                >
                  {!n.read && <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-primary" />}
                  <div className="min-w-0 flex-1">
                    <p className="font-medium leading-tight">{n.title}</p>
                    <p className="mt-0.5 text-xs text-muted-foreground">{n.body}</p>
                    <p className="mt-1 text-[10px] text-muted-foreground/70">
                      {formatDistanceToNow(new Date(n.created_at), { addSuffix: true })}
                    </p>
                  </div>
                  <div className="flex flex-col gap-1 opacity-0 group-hover:opacity-100">
                    {!n.read && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          markRead.mutate(n.id);
                        }}
                        className="text-muted-foreground hover:text-primary"
                        title="Mark read"
                      >
                        <Check className="h-3 w-3" />
                      </button>
                    )}
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        deleteNotif.mutate(n.id);
                      }}
                      className="text-muted-foreground hover:text-destructive"
                      title="Delete"
                    >
                      <Trash2 className="h-3 w-3" />
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </ScrollArea>
        <div className="border-t p-2">
          <Link to="/notifications" onClick={() => setOpen(false)}>
            <Button variant="ghost" size="sm" className="w-full text-xs">
              View all
            </Button>
          </Link>
        </div>
      </PopoverContent>
    </Popover>
  );
};

export default NotificationBell;