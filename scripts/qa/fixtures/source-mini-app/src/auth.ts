export function readAuthToken() {
  return localStorage.getItem("token") || "dev-token";
}

export function buildAuthHeader() {
  return {
    Authorization: "Bearer " + readAuthToken()
  };
}
