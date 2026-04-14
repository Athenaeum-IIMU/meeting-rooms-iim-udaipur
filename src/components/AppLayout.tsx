import { Link, useLocation } from "react-router-dom";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { CalendarDays, ClipboardList, Shield, LogOut, Menu, X } from "lucide-react";
import { useState } from "react";

const AppLayout: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { profile, isAdmin, signOut } = useAuth();
  const location = useLocation();
  const [mobileOpen, setMobileOpen] = useState(false);

  const links = [
    { to: "/", label: "Calendar", icon: CalendarDays },
    { to: "/my-bookings", label: "My Bookings", icon: ClipboardList },
    ...(isAdmin ? [{ to: "/admin", label: "Admin", icon: Shield }] : []),
  ];

  return (
    <div className="min-h-screen bg-background">
      <header className="sticky top-0 z-50 border-b bg-card/80 backdrop-blur-sm">
        <div className="container mx-auto flex h-16 items-center justify-between px-4">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary">
              <CalendarDays className="h-5 w-5 text-primary-foreground" />
            </div>
            <div>
              <h1 className="text-lg font-bold leading-none">IIM Udaipur</h1>
              <p className="text-xs text-muted-foreground">Room Scheduler</p>
            </div>
          </div>

          <nav className="hidden items-center gap-1 md:flex">
            {links.map((link) => (
              <Link key={link.to} to={link.to}>
                <Button
                  variant={location.pathname === link.to ? "secondary" : "ghost"}
                  size="sm"
                  className="gap-2"
                >
                  <link.icon className="h-4 w-4" />
                  {link.label}
                </Button>
              </Link>
            ))}
          </nav>

          <div className="flex items-center gap-2">
            <span className="hidden text-sm text-muted-foreground md:block">
              {profile?.full_name || profile?.email}
            </span>
            <Button variant="ghost" size="icon" onClick={signOut} title="Sign out">
              <LogOut className="h-4 w-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              className="md:hidden"
              onClick={() => setMobileOpen(!mobileOpen)}
            >
              {mobileOpen ? <X className="h-4 w-4" /> : <Menu className="h-4 w-4" />}
            </Button>
          </div>
        </div>

        {mobileOpen && (
          <div className="border-t bg-card px-4 py-2 md:hidden">
            {links.map((link) => (
              <Link key={link.to} to={link.to} onClick={() => setMobileOpen(false)}>
                <Button
                  variant={location.pathname === link.to ? "secondary" : "ghost"}
                  className="w-full justify-start gap-2"
                >
                  <link.icon className="h-4 w-4" />
                  {link.label}
                </Button>
              </Link>
            ))}
          </div>
        )}
      </header>

      <main className="container mx-auto px-4 py-6">{children}</main>
    </div>
  );
};

export default AppLayout;
