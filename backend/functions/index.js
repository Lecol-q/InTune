const { initializeApp } = require("firebase-admin/app");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");
const { defineString } = require("firebase-functions/params");
const { HttpsError, onCall } = require("firebase-functions/v2/https");

initializeApp();
const db = getFirestore();
const spotifyClientId = defineString("SPOTIFY_CLIENT_ID");
const spotifyRedirectUri = defineString("SPOTIFY_REDIRECT_URI");
const region = "us-central1";

function requireUID(request) {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to your InTune account first.");
  return request.auth.uid;
}

function connectionRef(uid) {
  return db.collection("spotifyConnections").doc(uid);
}

async function spotifyToken(fields) {
  const body = new URLSearchParams({ client_id: spotifyClientId.value(), ...fields });
  const response = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const result = await response.json();
  if (!response.ok) {
    const message = result.error_description || "Spotify authorization failed. Reconnect Spotify and try again.";
    throw new HttpsError("failed-precondition", message);
  }
  return result;
}

async function saveRefreshToken(uid, refreshToken) {
  await connectionRef(uid).set({
    refreshToken,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

async function accessTokenFor(uid) {
  const ref = connectionRef(uid);
  const saved = await ref.get();
  const refreshToken = saved.get("refreshToken");
  if (typeof refreshToken !== "string" || refreshToken.length === 0) {
    throw new HttpsError("failed-precondition", "Connect Spotify to this InTune account first.");
  }

  try {
    const refreshed = await spotifyToken({ grant_type: "refresh_token", refresh_token: refreshToken });
    if (refreshed.refresh_token) await saveRefreshToken(uid, refreshed.refresh_token);
    return refreshed.access_token;
  } catch (error) {
    if (error instanceof HttpsError && error.message.toLowerCase().includes("refresh token")) {
      await ref.delete();
      throw new HttpsError("failed-precondition", "Your Spotify connection expired. Reconnect Spotify.");
    }
    throw error;
  }
}

async function spotifyGET(uid, path) {
  const token = await accessTokenFor(uid);
  const response = await fetch(`https://api.spotify.com/v1${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) {
    if (response.status === 401) {
      await connectionRef(uid).delete();
      throw new HttpsError("failed-precondition", "Your Spotify connection expired. Reconnect Spotify.");
    }
    if (response.status === 403) {
      throw new HttpsError("permission-denied", "Spotify denied access. Confirm user-top-read access for this app.");
    }
    if (response.status === 429) {
      throw new HttpsError("resource-exhausted", "Spotify is limiting requests. Wait a moment and try again.");
    }
    throw new HttpsError("unavailable", `Spotify could not load your music (HTTP ${response.status}).`);
  }
  return response.json();
}

exports.spotifyStatus = onCall({ region }, async (request) => {
  const uid = requireUID(request);
  const saved = await connectionRef(uid).get();
  return { connected: saved.exists && typeof saved.get("refreshToken") === "string" };
});

exports.connectSpotify = onCall({ region }, async (request) => {
  const uid = requireUID(request);
  const { code, codeVerifier, redirectUri } = request.data || {};
  if (typeof code !== "string" || typeof codeVerifier !== "string" || redirectUri !== spotifyRedirectUri.value()) {
    throw new HttpsError("invalid-argument", "Spotify authorization response was incomplete or used an unexpected redirect URI.");
  }
  const result = await spotifyToken({
    grant_type: "authorization_code",
    code,
    redirect_uri: spotifyRedirectUri.value(),
    code_verifier: codeVerifier,
  });
  if (typeof result.refresh_token !== "string") {
    throw new HttpsError("failed-precondition", "Spotify did not return a refresh token. Reconnect and try again.");
  }
  await saveRefreshToken(uid, result.refresh_token);
  return { connected: true };
});

// One-time migration for phones that already have the older local Keychain token.
exports.migrateSpotifyConnection = onCall({ region }, async (request) => {
  const uid = requireUID(request);
  const refreshToken = request.data?.refreshToken;
  if (typeof refreshToken !== "string" || refreshToken.length === 0) {
    throw new HttpsError("invalid-argument", "The saved Spotify connection could not be migrated.");
  }
  const refreshed = await spotifyToken({ grant_type: "refresh_token", refresh_token: refreshToken });
  await saveRefreshToken(uid, refreshed.refresh_token || refreshToken);
  return { connected: true };
});

exports.importSpotifyTaste = onCall({ region }, async (request) => {
  const uid = requireUID(request);
  const [artists, tracks] = await Promise.all([
    spotifyGET(uid, "/me/top/artists?time_range=medium_term&limit=10"),
    spotifyGET(uid, "/me/top/tracks?time_range=medium_term&limit=50"),
  ]);
  return { artists: artists.items || [], tracks: tracks.items || [] };
});

exports.disconnectSpotify = onCall({ region }, async (request) => {
  const uid = requireUID(request);
  await connectionRef(uid).delete();
  return { connected: false };
});
