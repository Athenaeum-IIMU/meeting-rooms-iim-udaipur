import { useState, useMemo } from "react";
import { useRooms } from "@/hooks/useRooms";
import { useWeekBookings, useBlockedSlots, useBookingsRealtime } from "@/hooks/useBookings";
import BookingModal from "@/components/BookingModal";
import { Button } from "@/components/ui/button";
import { ChevronLeft, ChevronRight, Plus, CircleCheck } from "lucide-react";
import { cn } from "@/lib/utils";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { useToast } from "@/hooks/use-toast";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";

const HOURS = Array.from({ length: 24 }, (_, i) => i);

function getWeekDates(baseDate: Date): Date[] {
  const day = baseDate.getDay();
  const monday = new Date(baseDate);
  monday.setDate(baseDate.getDate() - ((day + 6) % 7));
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(monday);
    d.setDate(monday.getDate() + i);
    return d;
  });
}

function formatDate(d: Date): string {
  // Use LOCAL date components so IST users see IST dates.
  // Using toISOString() would convert to UTC and shift the date back
  // for anyone browsing between 00:00 and 05:29 IST.
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

const DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const statusColors: Record<string, string> = {
  approved: "bg-green-500/20 border-green-500 text-green-800",
  pending_admin: "bg-yellow-500/20 border-yellow-500 text-yellow-800",
  pending_members: "bg-orange-400/20 border-orange-400 text-orange-800",
  rejected: "bg-red-500/20 border-red-500 text-red-800",
  cancelled: "bg-muted border-muted-foreground/30 text-muted-foreground",
  needs_replacement: "bg-red-500/10 border-red-400 text-red-700",
};

const toMinutes = (time: string) => {
  const [hours, minutes] = time.split(":").map(Number);
  return hours * 60 + minutes;
};

const overlapsHour = (startTime: string, endTime: string, hour: number) => {
  const slotStart = hour * 60;
  const slotEnd = slotStart + 60;
  return toMinutes(startTime) < slotEnd && toMinutes(endTime) > slotStart;
};

const startsInHour = (startTime: string, hour: number) => {
  const start = toMinutes(startTime);
  return start >= hour * 60 && start < (hour + 1) * 60;
};

const Index = () => {
  const [baseDate, setBaseDate] = useState(new Date());
  useBookingsRealtime();
  const [modalOpen, setModalOpen] = useState(false);
  const [selectedSlot, setSelectedSlot] = useState<{
    date?: string;
    time?: string;
    endTime?: string;
    roomId?: string;
  }>({});
  const [selectedRoom, setSelectedRoom] = useState<string | null>(null);
  const [waitlistSlot, setWaitlistSlot] = useState<{
    roomId: string;
    roomName: string;
    date: string;
    hour: number;
  } | null>(null);
  const { user } = useAuth();
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const joinWaitlist = useMutation({
    mutationFn: async (slot: { roomId: string; date: string; hour: number }) => {
      if (!user) throw new Error("Sign in required");
      const start_time = `${String(slot.hour).padStart(2, "0")}:00:00`;
      const end_time = `${String(slot.hour + 1).padStart(2, "0")}:00:00`;
      const { error } = await supabase.from("waitlist").insert({
        user_id: user.id,
        room_id: slot.roomId,
        date: slot.date,
        start_time,
        end_time,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast({
        title: "Added to waitlist",
        description: "You'll be notified if this slot frees up.",
      });
      setWaitlistSlot(null);
      queryClient.invalidateQueries({ queryKey: ["waitlist"] });
    },
    onError: (e: Error) => {
      const msg = e.message.includes("duplicate")
        ? "You're already on the waitlist for this slot."
        : e.message;
      toast({ title: "Couldn't join waitlist", description: msg, variant: "destructive" });
    },
  });

  const weekDates = useMemo(() => getWeekDates(baseDate), [baseDate]);
  const startDate = formatDate(weekDates[0]);
  const endDate = formatDate(weekDates[6]);

  const { data: rooms } = useRooms();
  const { data: bookings } = useWeekBookings(startDate, endDate);
  const { data: blockedSlots } = useBlockedSlots(startDate, endDate);

  const filteredRooms = selectedRoom ? rooms?.filter((r) => r.id === selectedRoom) : rooms;

  // Compute "rooms free right now" for today
  const now = new Date();
  const todayStr = formatDate(now);
  const currentHour = now.getHours();
  const roomsFreeNow = useMemo(() => {
    if (!rooms) return { free: 0, total: 0, freeNames: [] as string[] };
    const freeNames: string[] = [];
    for (const r of rooms) {
      const occupied = bookings?.some(
        (b) =>
          b.room_id === r.id &&
          b.date === todayStr &&
          ["approved", "pending_admin", "pending_members"].includes(b.status) &&
          overlapsHour(b.start_time, b.end_time, currentHour)
      );
      const blocked = blockedSlots?.some(
        (bs) =>
          bs.room_id === r.id &&
          bs.date === todayStr &&
          overlapsHour(bs.start_time, bs.end_time, currentHour)
      );
      if (!occupied && !blocked) freeNames.push(r.name);
    }
    return { free: freeNames.length, total: rooms.length, freeNames };
  }, [rooms, bookings, blockedSlots, todayStr, currentHour]);

  const prevWeek = () => {
    const d = new Date(baseDate);
    d.setDate(d.getDate() - 7);
    setBaseDate(d);
  };
  const nextWeek = () => {
    const d = new Date(baseDate);
    d.setDate(d.getDate() + 7);
    setBaseDate(d);
  };
  const goToday = () => setBaseDate(new Date());

  const fmtTime = (mins: number) =>
    `${String(Math.floor(mins / 60)).padStart(2, "0")}:${String(mins % 60).padStart(2, "0")}`;

  const handleSlotClick = (
    date: string,
    roomId: string,
    startMin: number,
    endMin: number,
  ) => {
    setSelectedSlot({
      date,
      time: fmtTime(startMin),
      endTime: fmtTime(endMin),
      roomId,
    });
    setModalOpen(true);
  };

  /** Free sub-ranges within [hour, hour+1) given existing bookings + blocked slots. */
  const getFreeGaps = (roomId: string, date: string, hour: number) => {
    const slotStart = hour * 60;
    const slotEnd = slotStart + 60;
    const busy: Array<[number, number]> = [];
    bookings?.forEach((b) => {
      if (
        b.room_id === roomId &&
        b.date === date &&
        !["cancelled", "rejected"].includes(b.status) &&
        overlapsHour(b.start_time, b.end_time, hour)
      ) {
        busy.push([
          Math.max(toMinutes(b.start_time), slotStart),
          Math.min(toMinutes(b.end_time), slotEnd),
        ]);
      }
    });
    blockedSlots?.forEach((bs) => {
      if (
        bs.room_id === roomId &&
        bs.date === date &&
        overlapsHour(bs.start_time, bs.end_time, hour)
      ) {
        busy.push([
          Math.max(toMinutes(bs.start_time), slotStart),
          Math.min(toMinutes(bs.end_time), slotEnd),
        ]);
      }
    });
    busy.sort((a, b) => a[0] - b[0]);
    const gaps: Array<[number, number]> = [];
    let cursor = slotStart;
    for (const [s, e] of busy) {
      if (s > cursor) gaps.push([cursor, s]);
      cursor = Math.max(cursor, e);
    }
    if (cursor < slotEnd) gaps.push([cursor, slotEnd]);
    return gaps;
  };

  const getBookingsForSlot = (roomId: string, date: string, hour: number) => {
    return bookings?.filter(
      (b) =>
        b.room_id === roomId &&
        b.date === date &&
        !["cancelled", "rejected"].includes(b.status) &&
        overlapsHour(b.start_time, b.end_time, hour)
    ) || [];
  };

  const isBlocked = (roomId: string, date: string, hour: number) => {
    return blockedSlots?.some(
      (bs) =>
        bs.room_id === roomId &&
        bs.date === date &&
        overlapsHour(bs.start_time, bs.end_time, hour)
    );
  };

  const today = formatDate(new Date());

  return (
    <div className="space-y-4">
      {rooms && rooms.length > 0 && (
        <div className="flex flex-wrap items-center gap-2 rounded-lg border bg-card p-3 text-sm">
          <CircleCheck
            className={cn(
              "h-4 w-4",
              roomsFreeNow.free > 0 ? "text-green-600" : "text-muted-foreground"
            )}
          />
          <span className="font-medium">
            {roomsFreeNow.free} of {roomsFreeNow.total} rooms free right now
          </span>
          {roomsFreeNow.freeNames.length > 0 && (
            <span className="text-muted-foreground">
              · {roomsFreeNow.freeNames.join(", ")}
            </span>
          )}
        </div>
      )}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Button variant="outline" size="icon" onClick={prevWeek}>
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <Button variant="outline" size="sm" onClick={goToday}>Today</Button>
          <Button variant="outline" size="icon" onClick={nextWeek}>
            <ChevronRight className="h-4 w-4" />
          </Button>
          <span className="text-sm font-medium text-muted-foreground">
            {weekDates[0].toLocaleDateString("en-IN", { month: "short", day: "numeric" })} –{" "}
            {weekDates[6].toLocaleDateString("en-IN", { month: "short", day: "numeric", year: "numeric" })}
          </span>
        </div>

        <div className="flex w-full items-center gap-2 sm:w-auto">
          <div className="flex flex-1 gap-1 overflow-x-auto sm:flex-none">
            <Button
              variant={selectedRoom === null ? "secondary" : "ghost"}
              size="sm"
              className="shrink-0"
              onClick={() => setSelectedRoom(null)}
            >
              All
            </Button>
            {rooms?.map((room) => (
              <Button
                key={room.id}
                variant={selectedRoom === room.id ? "secondary" : "ghost"}
                size="sm"
                className="shrink-0"
                onClick={() => setSelectedRoom(room.id)}
              >
                {room.name}
              </Button>
            ))}
          </div>
        </div>
      </div>

      <Button
        onClick={() => { setSelectedSlot({}); setModalOpen(true); }}
        className="fixed bottom-4 right-4 z-50 gap-1 rounded-full px-4 h-11 shadow-lg sm:bottom-6 sm:right-6 sm:h-12 sm:px-6"
        size="lg"
      >
        <Plus className="h-5 w-5" /> Book
      </Button>

      {/* Legend */}
      <div className="flex flex-wrap gap-4 text-xs text-muted-foreground">
        <span className="flex items-center gap-1"><span className="h-3 w-3 rounded border border-green-500 bg-green-500/20" /> Approved</span>
        <span className="flex items-center gap-1"><span className="h-3 w-3 rounded border border-yellow-500 bg-yellow-500/20" /> Pending Admin</span>
        <span className="flex items-center gap-1"><span className="h-3 w-3 rounded border border-orange-400 bg-orange-400/20" /> Pending Members</span>
        <span className="flex items-center gap-1"><span className="h-3 w-3 rounded border border-red-500 bg-red-500/20" /> Rejected</span>
        <span className="flex items-center gap-1"><span className="h-3 w-3 rounded border-2 border-destructive bg-destructive/25" /> Blocked</span>
      </div>

      <div className="overflow-auto rounded-lg border bg-card">
        <div className="min-w-[800px]">
          {/* Header - sticky so it stays visible while scrolling */}
          <div
            className="sticky top-0 z-20 grid border-b bg-muted/95 backdrop-blur supports-[backdrop-filter]:bg-muted/80 shadow-sm"
            style={{ gridTemplateColumns: `80px repeat(${weekDates.length}, 1fr)` }}
          >
            <div className="p-2 text-xs font-medium text-muted-foreground">Time</div>
            {weekDates.map((d, i) => (
              <div
                key={i}
                className={cn(
                  "p-2 text-center text-xs font-medium",
                  formatDate(d) === today && "bg-primary/10 text-primary"
                )}
              >
                <div>{DAY_NAMES[i]}</div>
                <div className="text-lg font-bold">{d.getDate()}</div>
              </div>
            ))}
          </div>

          {/* Time grid */}
          {HOURS.map((hour) => (
            <div
              key={hour}
              className="grid border-b last:border-b-0"
              style={{ gridTemplateColumns: `80px repeat(${weekDates.length}, 1fr)` }}
            >
              <div className="flex items-start p-2 text-xs text-muted-foreground">
                {String(hour).padStart(2, "0")}:00
              </div>
              {weekDates.map((d, di) => {
                const dateStr = formatDate(d);
                return (
                  <div key={di} className={cn("min-h-[3rem] border-l p-0.5", formatDate(d) === today && "bg-primary/5")}>
                    {filteredRooms?.map((room) => {
                      const slotBookings = getBookingsForSlot(room.id, dateStr, hour);
                      const blockedHere =
                        blockedSlots?.filter(
                          (bs) =>
                            bs.room_id === room.id &&
                            bs.date === dateStr &&
                            overlapsHour(bs.start_time, bs.end_time, hour),
                        ) || [];
                      const gaps = getFreeGaps(room.id, dateStr, hour);

                      const items: JSX.Element[] = [];

                      blockedHere.forEach((bs) => {
                        if (!startsInHour(bs.start_time, hour)) return;
                        items.push(
                          <div
                            key={`bl-${bs.id}`}
                            className="mb-0.5 max-w-full rounded border-2 border-destructive bg-destructive/25 px-1 py-0.5 text-[10px] font-semibold leading-tight text-destructive shadow-sm"
                            title={bs.reason ? `Blocked: ${bs.reason}` : "Blocked slot"}
                          >
                            <div className="flex flex-wrap items-center gap-0.5">
                              <span className="font-bold">🚫 {room.name}</span>
                              <span>{bs.start_time.slice(0, 5)}–{bs.end_time.slice(0, 5)}</span>
                            </div>
                            {bs.reason && (
                              <div className="max-w-full font-normal break-words opacity-90">{bs.reason}</div>
                            )}
                          </div>,
                        );
                      });

                      slotBookings.forEach((b) => {
                        if (!startsInHour(b.start_time, hour)) return;
                        items.push(
                          <div
                            key={b.id}
                            className={cn(
                              "mb-0.5 rounded border px-1 py-0.5 text-[10px] leading-tight",
                              b.user_id !== user?.id ? "cursor-pointer hover:opacity-80" : "cursor-default",
                              statusColors[b.status] || "",
                            )}
                            title={
                              b.user_id !== user?.id
                                ? `${b.title} (${b.start_time}–${b.end_time}) — click to join waitlist`
                                : `${b.title} (${b.start_time}–${b.end_time}) - ${b.status}`
                            }
                            onClick={() => {
                              if (b.user_id !== user?.id) {
                                setWaitlistSlot({
                                  roomId: room.id,
                                  roomName: room.name,
                                  date: dateStr,
                                  hour,
                                });
                              }
                            }}
                          >
                            <span className="font-medium">{room.name}</span>: {b.title}
                            <div className="opacity-70">{b.start_time.slice(0, 5)}–{b.end_time.slice(0, 5)}</div>
                          </div>,
                        );
                      });

                      const hasBusy = slotBookings.length > 0 || blockedHere.length > 0;

                      gaps.forEach(([s, e]) => {
                        // When the whole hour is free, show the room name as before.
                        // When only part of the hour is free, show the exact free window.
                        const isWhole = !hasBusy;
                        if (!isWhole && e - s < 30) return; // skip gaps too short to book
                        items.push(
                          <div
                            key={`gap-${s}`}
                            className="mb-0.5 cursor-pointer rounded px-1 py-0.5 text-[10px] text-muted-foreground/40 hover:bg-primary/10 hover:text-primary"
                            onClick={() => handleSlotClick(dateStr, room.id, s, e)}
                            title={isWhole ? `Book ${room.name}` : `Free ${fmtTime(s)}–${fmtTime(e)}`}
                          >
                            {isWhole ? room.name : `${room.name} · free ${fmtTime(s)}–${fmtTime(e)}`}
                          </div>,
                        );
                      });

                      return <div key={room.id}>{items}</div>;
                    })}
                  </div>
                );
              })}
            </div>
          ))}
        </div>
      </div>

      <BookingModal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        defaultDate={selectedSlot.date}
        defaultTime={selectedSlot.time}
        defaultEndTime={selectedSlot.endTime}
        defaultRoomId={selectedSlot.roomId}
      />

      <Dialog open={!!waitlistSlot} onOpenChange={(o) => !o && setWaitlistSlot(null)}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Join the waitlist?</DialogTitle>
          </DialogHeader>
          {waitlistSlot && (
            <p className="text-sm text-muted-foreground">
              This slot in <strong>{waitlistSlot.roomName}</strong> on{" "}
              <strong>{waitlistSlot.date}</strong> at{" "}
              <strong>{String(waitlistSlot.hour).padStart(2, "0")}:00</strong> is taken.
              We'll notify you if it frees up so you can book it.
            </p>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setWaitlistSlot(null)}>
              Cancel
            </Button>
            <Button
              disabled={joinWaitlist.isPending}
              onClick={() =>
                waitlistSlot &&
                joinWaitlist.mutate({
                  roomId: waitlistSlot.roomId,
                  date: waitlistSlot.date,
                  hour: waitlistSlot.hour,
                })
              }
            >
              {joinWaitlist.isPending ? "Adding…" : "Join waitlist"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

export default Index;
