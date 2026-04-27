import { useEffect, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { useRooms } from "@/hooks/useRooms";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { useToast } from "@/hooks/use-toast";
import { Pencil, Plus, Trash2, MapPin, Users } from "lucide-react";

const AdminRoomsTab = () => {
  const { data: rooms } = useRooms();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const [editing, setEditing] = useState<any | null>(null);
  const [creating, setCreating] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<any | null>(null);

  const removeRoom = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.from("rooms").delete().eq("id", id);
      if (error) throw error;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["rooms"] });
      toast({ title: "Room deleted" });
      setDeleteTarget(null);
    },
    onError: (e: Error) =>
      toast({ title: "Couldn't delete", description: e.message, variant: "destructive" }),
  });

  return (
    <div className="space-y-3">
      <div className="flex justify-end">
        <Button size="sm" onClick={() => setCreating(true)} className="gap-1">
          <Plus className="h-3 w-3" /> Add room
        </Button>
      </div>

      {rooms?.length === 0 && (
        <p className="text-sm text-muted-foreground">No rooms configured yet.</p>
      )}

      {rooms?.map((r) => (
        <Card key={r.id}>
          <CardContent className="flex items-start justify-between gap-3 p-3">
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <h3 className="font-semibold">{r.name}</h3>
              </div>
              <div className="mt-0.5 flex flex-wrap gap-x-3 gap-y-1 text-xs text-muted-foreground">
                <span className="flex items-center gap-1">
                  <Users className="h-3 w-3" /> Capacity {r.capacity} · Min {r.min_members}
                </span>
                {r.location && (
                  <span className="flex items-center gap-1">
                    <MapPin className="h-3 w-3" /> {r.location}
                  </span>
                )}
              </div>
              {r.description && (
                <p className="mt-1 text-xs text-foreground/70">{r.description}</p>
              )}
            </div>
            <div className="flex gap-1">
              <Button variant="ghost" size="icon" onClick={() => setEditing(r)} title="Edit">
                <Pencil className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => setDeleteTarget(r)}
                title="Delete"
              >
                <Trash2 className="h-4 w-4 text-destructive" />
              </Button>
            </div>
          </CardContent>
        </Card>
      ))}

      <RoomFormDialog
        open={creating || !!editing}
        onClose={() => {
          setCreating(false);
          setEditing(null);
        }}
        room={editing}
      />

      <Dialog open={!!deleteTarget} onOpenChange={(o) => !o && setDeleteTarget(null)}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Delete this room?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            "{deleteTarget?.name}" will be removed. Existing bookings for this room will keep their record but the room reference will be lost.
          </p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteTarget(null)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={() => removeRoom.mutate(deleteTarget.id)}
              disabled={removeRoom.isPending}
            >
              {removeRoom.isPending ? "Deleting…" : "Delete"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
};

const RoomFormDialog = ({
  open,
  onClose,
  room,
}: {
  open: boolean;
  onClose: () => void;
  room: any | null;
}) => {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const [name, setName] = useState("");
  const [capacity, setCapacity] = useState(4);
  const [minMembers, setMinMembers] = useState(3);
  const [location, setLocation] = useState("");
  const [description, setDescription] = useState("");

  useEffect(() => {
    if (open) {
      setName(room?.name || "");
      setCapacity(room?.capacity ?? 4);
      setMinMembers(room?.min_members ?? 3);
      setLocation(room?.location || "");
      setDescription(room?.description || "");
    }
  }, [open, room]);

  const handleClose = () => {
    setName("");
    setCapacity(4);
    setMinMembers(3);
    setLocation("");
    setDescription("");
    onClose();
  };

  const save = useMutation({
    mutationFn: async () => {
      const payload = {
        name,
        capacity,
        min_members: minMembers,
        location: location || null,
        description: description || null,
      };
      if (room) {
        const { error } = await supabase.from("rooms").update(payload).eq("id", room.id);
        if (error) throw error;
      } else {
        const { error } = await supabase.from("rooms").insert(payload);
        if (error) throw error;
      }
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["rooms"] });
      toast({ title: room ? "Room updated" : "Room added" });
      handleClose();
    },
    onError: (e: Error) =>
      toast({ title: "Save failed", description: e.message, variant: "destructive" }),
  });

  return (
    <Dialog open={open} onOpenChange={(o) => !o && handleClose()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{room ? "Edit room" : "Add room"}</DialogTitle>
        </DialogHeader>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            save.mutate();
          }}
          className="space-y-3"
        >
          <div className="space-y-1">
            <Label>Name</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} required />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <Label>Capacity</Label>
              <Input
                type="number"
                min={1}
                value={capacity}
                onChange={(e) => setCapacity(parseInt(e.target.value) || 1)}
                required
              />
            </div>
            <div className="space-y-1">
              <Label>Min members</Label>
              <Input
                type="number"
                min={1}
                value={minMembers}
                onChange={(e) => setMinMembers(parseInt(e.target.value) || 1)}
                required
              />
            </div>
          </div>
          <div className="space-y-1">
            <Label>Location</Label>
            <Input
              value={location}
              onChange={(e) => setLocation(e.target.value)}
              placeholder="e.g. Library, 2nd floor"
            />
          </div>
          <div className="space-y-1">
            <Label>Description</Label>
            <Textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Whiteboard, projector, etc."
              rows={3}
            />
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={handleClose}>
              Cancel
            </Button>
            <Button type="submit" disabled={save.isPending}>
              {save.isPending ? "Saving…" : "Save"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
};

export default AdminRoomsTab;