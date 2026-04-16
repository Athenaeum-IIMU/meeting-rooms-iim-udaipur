import { useState, useMemo } from "react";
import { useRooms } from "@/hooks/useRooms";
import { useWeekBookings, useBlockedSlots } from "@/hooks/useBookings";
import BookingModal from "@/components/BookingModal";
import { Button } from "@/components/ui/button";
import { ChevronLeft, ChevronRight, Plus } from "lucide-react";
import { cn } from "@/lib/utils";

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
  return d.toISOString().split("T")[0];
}

const DAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const statusColors: Record<string, string> = {
  approved: "bg-green-500/20 border-green-500 text-green-800",
  pending_admin: "bg-yellow-500/20 border-yellow-500 text-yellow-800",
  pending_members: "bg-orange-400/20 border-orange-400 text-orange-800",
  rejected: "bg-red-500/20 border-red-500 text-red-800",
  cancelled: "bg-muted border-muted-foreground/30 text-muted-foreground",
};

const Index = () => {
  const [baseDate, setBaseDate] = useState(new Date());
  const [modalOpen, setModalOpen] = useState(false);
  const [selectedSlot, setSelectedSlot] = useState<{
    date?: string;
    time?: string;
    roomId?: string;
  }>({});
  const [selectedRoom, setSelectedRoom] = useState<string | null>(null);

  const weekDates = useMemo(() => getWeekDates(baseDate), [baseDate]);
  const startDate = formatDate(weekDates[0]);
  const endDate = formatDate(weekDates[6]);

  const { data: rooms } = useRooms();
  const { data: bookings } = useWeekBookings(startDate, endDate);
  const { data: blockedSlots } = useBlockedSlots(startDate, endDate);

  const filteredRooms = selectedRoom ? rooms?.filter((r) => r.id === selectedRoom) : rooms;

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

  const handleSlotClick = (date: string, hour: number, roomId: string) => {
    setSelectedSlot({
      date,
      time: `${String(hour).padStart(2, "0")}:00`,
      roomId,
    });
    setModalOpen(true);
  };

  const getBookingsForSlot = (roomId: string, date: string, hour: number) => {
    return bookings?.filter(
      (b) =>
        b.room_id === roomId &&
        b.date === date &&
        parseInt(b.start_time.split(":")[0]) <= hour &&
        parseInt(b.end_time.split(":")[0]) > hour
    ) || [];
  };

  const isBlocked = (roomId: string, date: string, hour: number) => {
    return blockedSlots?.some(
      (bs) =>
        bs.room_id === roomId &&
        bs.date === date &&
        parseInt(bs.start_time.split(":")[0]) <= hour &&
        parseInt(bs.end_time.split(":")[0]) > hour
    );
  };

  const today = formatDate(new Date());

  return (
    <div className="space-y-4">
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

        <div className="flex items-center gap-2">
          <div className="flex gap-1">
            <Button
              variant={selectedRoom === null ? "secondary" : "ghost"}
              size="sm"
              onClick={() => setSelectedRoom(null)}
            >
              All
            </Button>
            {rooms?.map((room) => (
              <Button
                key={room.id}
                variant={selectedRoom === room.id ? "secondary" : "ghost"}
                size="sm"
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
        className="fixed bottom-6 right-6 z-50 gap-1 shadow-lg rounded-full px-6 h-12"
        size="lg"
      >
        <Plus className="h-5 w-5" /> Book
        </div>
      </div>

      {/* Legend */}
      <div className="flex flex-wrap gap-4 text-xs text-muted-foreground">
        <span className="flex items-center gap-1"><span className="h-3 w-3 rounded border border-green-500 bg-green-500/20" /> Approved</span>
        <span className="flex items-center gap-1"><span className="h-3 w-3 rounded border border-yellow-500 bg-yellow-500/20" /> Pending Admin</span>
        <span className="flex items-center gap-1"><span className="h-3 w-3 rounded border border-orange-400 bg-orange-400/20" /> Pending Members</span>
        <span className="flex items-center gap-1"><span className="h-3 w-3 rounded border border-red-500 bg-red-500/20" /> Rejected</span>
        <span className="flex items-center gap-1"><span className="h-3 w-3 rounded border border-dashed border-destructive/40 bg-destructive/10" /> Blocked</span>
      </div>

      <div className="overflow-auto rounded-lg border bg-card">
        <div className="min-w-[800px]">
          {/* Header */}
          <div className="grid border-b bg-muted/50" style={{ gridTemplateColumns: `80px repeat(${weekDates.length}, 1fr)` }}>
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
                      const blocked = isBlocked(room.id, dateStr, hour);

                      if (blocked) {
                        return (
                          <div key={room.id} className="mb-0.5 rounded border border-dashed border-destructive/40 bg-destructive/10 px-1 py-0.5 text-[10px] text-destructive">
                            🚫 {room.name}
                          </div>
                        );
                      }

                      if (slotBookings.length > 0) {
                        return slotBookings.map((b) => {
                          const isStart = parseInt(b.start_time.split(":")[0]) === hour;
                          if (!isStart) return null;
                          return (
                            <div
                              key={b.id}
                              className={cn(
                                "mb-0.5 cursor-default rounded border px-1 py-0.5 text-[10px] leading-tight",
                                statusColors[b.status] || ""
                              )}
                              title={`${b.title} (${b.start_time}–${b.end_time}) - ${b.status}`}
                            >
                              <span className="font-medium">{room.name}</span>: {b.title}
                              <div className="opacity-70">{b.start_time.slice(0, 5)}–{b.end_time.slice(0, 5)}</div>
                            </div>
                          );
                        });
                      }

                      return (
                        <div
                          key={room.id}
                          className="mb-0.5 cursor-pointer rounded px-1 py-0.5 text-[10px] text-muted-foreground/40 hover:bg-primary/10 hover:text-primary"
                          onClick={() => handleSlotClick(dateStr, hour, room.id)}
                        >
                          {room.name}
                        </div>
                      );
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
        defaultRoomId={selectedSlot.roomId}
      />
    </div>
  );
};

export default Index;
