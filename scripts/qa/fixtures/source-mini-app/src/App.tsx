import { useEffect, useState } from "react";
import { fetchProfile } from "./api";
import { buildAuthHeader } from "./auth";

export function App() {
  const [profile, setProfile] = useState<any>(null);

  useEffect(() => {
    fetch("/api/bootstrap", { headers: buildAuthHeader() });
    fetchProfile("current").then(setProfile);
  }, []);

  return <pre>{JSON.stringify(profile)}</pre>;
}
