export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      audit_log: {
        Row: {
          action: string
          actor_email: string | null
          actor_id: string | null
          created_at: string
          details: Json | null
          id: string
          summary: string
          target_id: string | null
          target_type: string
        }
        Insert: {
          action: string
          actor_email?: string | null
          actor_id?: string | null
          created_at?: string
          details?: Json | null
          id?: string
          summary: string
          target_id?: string | null
          target_type: string
        }
        Update: {
          action?: string
          actor_email?: string | null
          actor_id?: string | null
          created_at?: string
          details?: Json | null
          id?: string
          summary?: string
          target_id?: string | null
          target_type?: string
        }
        Relationships: []
      }
      blocked_slots: {
        Row: {
          created_at: string
          created_by: string
          date: string
          end_time: string
          id: string
          reason: string | null
          room_id: string
          start_time: string
        }
        Insert: {
          created_at?: string
          created_by: string
          date: string
          end_time: string
          id?: string
          reason?: string | null
          room_id: string
          start_time: string
        }
        Update: {
          created_at?: string
          created_by?: string
          date?: string
          end_time?: string
          id?: string
          reason?: string | null
          room_id?: string
          start_time?: string
        }
        Relationships: [
          {
            foreignKeyName: "blocked_slots_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      booking_attempts: {
        Row: {
          booking_id: string | null
          created_at: string
          date: string | null
          end_time: string | null
          error_message: string | null
          id: string
          member_emails: string[] | null
          room_id: string | null
          start_time: string | null
          success: boolean
          title: string | null
          user_email: string | null
          user_id: string | null
        }
        Insert: {
          booking_id?: string | null
          created_at?: string
          date?: string | null
          end_time?: string | null
          error_message?: string | null
          id?: string
          member_emails?: string[] | null
          room_id?: string | null
          start_time?: string | null
          success: boolean
          title?: string | null
          user_email?: string | null
          user_id?: string | null
        }
        Update: {
          booking_id?: string | null
          created_at?: string
          date?: string | null
          end_time?: string | null
          error_message?: string | null
          id?: string
          member_emails?: string[] | null
          room_id?: string | null
          start_time?: string | null
          success?: boolean
          title?: string | null
          user_email?: string | null
          user_id?: string | null
        }
        Relationships: []
      }
      booking_members: {
        Row: {
          booking_id: string
          created_at: string
          email: string
          id: string
          status: string
          user_id: string | null
        }
        Insert: {
          booking_id: string
          created_at?: string
          email: string
          id?: string
          status?: string
          user_id?: string | null
        }
        Update: {
          booking_id?: string
          created_at?: string
          email?: string
          id?: string
          status?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "booking_members_booking_id_fkey"
            columns: ["booking_id"]
            isOneToOne: false
            referencedRelation: "bookings"
            referencedColumns: ["id"]
          },
        ]
      }
      bookings: {
        Row: {
          created_at: string
          date: string
          end_time: string
          id: string
          rejection_reason: string | null
          reminder_sent: boolean
          room_id: string
          start_time: string
          status: string
          title: string
          user_id: string
        }
        Insert: {
          created_at?: string
          date: string
          end_time: string
          id?: string
          rejection_reason?: string | null
          reminder_sent?: boolean
          room_id: string
          start_time: string
          status?: string
          title: string
          user_id: string
        }
        Update: {
          created_at?: string
          date?: string
          end_time?: string
          id?: string
          rejection_reason?: string | null
          reminder_sent?: boolean
          room_id?: string
          start_time?: string
          status?: string
          title?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "bookings_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      email_delivery_log: {
        Row: {
          booking_id: string | null
          created_at: string
          error: string | null
          id: string
          notification_id: string | null
          recipient: string
          status: string
          subject: string
          user_id: string | null
        }
        Insert: {
          booking_id?: string | null
          created_at?: string
          error?: string | null
          id?: string
          notification_id?: string | null
          recipient: string
          status?: string
          subject: string
          user_id?: string | null
        }
        Update: {
          booking_id?: string | null
          created_at?: string
          error?: string | null
          id?: string
          notification_id?: string | null
          recipient?: string
          status?: string
          subject?: string
          user_id?: string | null
        }
        Relationships: []
      }
      notifications: {
        Row: {
          body: string
          booking_id: string | null
          created_at: string
          id: string
          read: boolean
          title: string
          type: string
          user_id: string
        }
        Insert: {
          body: string
          booking_id?: string | null
          created_at?: string
          id?: string
          read?: boolean
          title: string
          type: string
          user_id: string
        }
        Update: {
          body?: string
          booking_id?: string | null
          created_at?: string
          id?: string
          read?: boolean
          title?: string
          type?: string
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          created_at: string
          email: string
          full_name: string
          id: string
          user_id: string
        }
        Insert: {
          created_at?: string
          email?: string
          full_name?: string
          id?: string
          user_id: string
        }
        Update: {
          created_at?: string
          email?: string
          full_name?: string
          id?: string
          user_id?: string
        }
        Relationships: []
      }
      rooms: {
        Row: {
          capacity: number
          created_at: string
          description: string | null
          id: string
          location: string | null
          min_members: number
          name: string
        }
        Insert: {
          capacity?: number
          created_at?: string
          description?: string | null
          id?: string
          location?: string | null
          min_members?: number
          name: string
        }
        Update: {
          capacity?: number
          created_at?: string
          description?: string | null
          id?: string
          location?: string | null
          min_members?: number
          name?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      waitlist: {
        Row: {
          created_at: string
          date: string
          end_time: string
          id: string
          note: string | null
          room_id: string
          start_time: string
          user_id: string
        }
        Insert: {
          created_at?: string
          date: string
          end_time: string
          id?: string
          note?: string | null
          room_id: string
          start_time: string
          user_id: string
        }
        Update: {
          created_at?: string
          date?: string
          end_time?: string
          id?: string
          note?: string | null
          room_id?: string
          start_time?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "waitlist_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_booking_invite_atomic: {
        Args: { p_accept: boolean; p_member_id: string }
        Returns: undefined
      }
      check_blocked_slot: {
        Args: {
          p_date: string
          p_end_time: string
          p_room_id: string
          p_start_time: string
        }
        Returns: boolean
      }
      check_booking_conflict: {
        Args: {
          p_date: string
          p_end_time: string
          p_exclude_booking_id?: string
          p_room_id: string
          p_start_time: string
        }
        Returns: boolean
      }
      check_user_time_overlap: {
        Args: {
          p_date: string
          p_end_time: string
          p_exclude_booking_id?: string
          p_start_time: string
          p_user_id: string
        }
        Returns: boolean
      }
      cleanup_old_data: { Args: never; Returns: undefined }
      cleanup_unapproved_past_bookings: { Args: never; Returns: undefined }
      create_booking_atomic: {
        Args: {
          p_date: string
          p_end_time: string
          p_member_emails?: string[]
          p_room_id: string
          p_start_time: string
          p_title: string
        }
        Returns: string
      }
      create_booking_logged: {
        Args: {
          p_date: string
          p_end_time: string
          p_member_emails?: string[]
          p_room_id: string
          p_start_time: string
          p_title: string
        }
        Returns: string
      }
      filter_unregistered_emails: {
        Args: { p_emails: string[] }
        Returns: string[]
      }
      get_actor_email: { Args: { _user_id: string }; Returns: string }
      get_calendar_busy_slots: {
        Args: { p_end_date: string; p_start_date: string }
        Returns: {
          date: string
          end_time: string
          id: string
          is_mine: boolean
          room_id: string
          start_time: string
          status: string
          title: string
          user_id: string
        }[]
      }
      get_send_email_secret: { Args: never; Returns: string }
      get_user_daily_hours: {
        Args: {
          p_date: string
          p_exclude_booking_id?: string
          p_user_id: string
        }
        Returns: string
      }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      is_current_user_admin: { Args: never; Returns: boolean }
      notify_user_by_email: {
        Args: {
          p_body: string
          p_booking_id?: string
          p_email: string
          p_title: string
          p_type: string
        }
        Returns: undefined
      }
      send_booking_reminders: { Args: never; Returns: undefined }
      shares_booking: {
        Args: { _target: string; _viewer: string }
        Returns: boolean
      }
    }
    Enums: {
      app_role: "admin" | "user"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "user"],
    },
  },
} as const
