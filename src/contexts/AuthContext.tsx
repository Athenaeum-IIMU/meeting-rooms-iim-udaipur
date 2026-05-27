import React, { createContext, useContext, useEffect, useState } from "react";
import { Session, User } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";

interface AuthContextType {
  session: Session | null;
  user: User | null;
  profile: { full_name: string; email: string } | null;
  isAdmin: boolean;
  loading: boolean;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  session: null,
  user: null,
  profile: null,
  isAdmin: false,
  loading: true,
  signOut: async () => {},
});

export const useAuth = () => useContext(AuthContext);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [session, setSession] = useState<Session | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<{ full_name: string; email: string } | null>(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
      setUser(session?.user ?? null);

      if (session?.user) {
        setTimeout(() => {
          fetchProfile(session.user.id);
          checkAdmin(session.user.id);
        }, 0);
      } else {
        setProfile(null);
        setIsAdmin(false);
        setLoading(false);
      }
    });

    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setUser(session?.user ?? null);
      if (session?.user) {
        fetchProfile(session.user.id);
        checkAdmin(session.user.id);
      } else {
        setLoading(false);
      }
    });

    return () => subscription.unsubscribe();
  }, []);

  const fetchProfile = async (userId: string) => {
    const { data } = await supabase
      .from("profiles")
      .select("full_name, email")
      .eq("user_id", userId)
      .single();
    setProfile(data);
    setLoading(false);
  };

  const checkAdmin = async (_userId: string) => {
    // Server-side check via SECURITY DEFINER RPC. Returns true only if the
    // caller's auth.uid() has the admin role — cannot be spoofed client-side.
    const { data, error } = await supabase.rpc("is_current_user_admin");
    setIsAdmin(!error && data === true);
  };

  const signOut = async () => {
    await supabase.auth.signOut();
  };

  return (
    <AuthContext.Provider value={{ session, user, profile, isAdmin, loading, signOut }}>
      {children}
    </AuthContext.Provider>
  );
};
