export async function fetchProfile(userId: string) {
  const response = await fetch("/api/profile/" + userId);
  return response.json();
}
