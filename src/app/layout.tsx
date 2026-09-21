import type { Metadata } from "next";
import "./globals.css";
import "./start-panel.css";

export const metadata: Metadata = {
  title: "Power Ludo",
  description: "A modern multiplayer strategy game with powered dice."
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
