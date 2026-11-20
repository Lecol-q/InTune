import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, deleteDoc, getDoc, getDocs, collection, query, where, serverTimestamp, Timestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-intune', firestore: {
    host: '127.0.0.1', port: 8189, rules: readFileSync('firestore.rules', 'utf8')
  }});
});
beforeEach(async () => { await env.clearFirestore(); });
after(async () => { await env.cleanup(); });
const db = uid => env.authenticatedContext(uid).firestore();
const profile = uid => ({ ownerID: uid, name: uid, age: 21, bio: 'Music fan', artists: ['Artist'],
  genres: ['hip hop'], showcase: 'A song', active: true });
async function publish(uid) { await setDoc(doc(db(uid), 'profiles', uid), profile(uid)); }
async function like(from, to) {
  await setDoc(doc(db(from), 'swipes', from, 'outgoing', to), {
    fromID: from, toID: to, decision: 'like', createdAt: serverTimestamp()
  });
}
async function match() {
  await publish('alice'); await publish('bob');
  await like('alice', 'bob'); await like('bob', 'alice');
  await setDoc(doc(db('alice'), 'matches', 'alice__bob'), { members: ['alice', 'bob'], createdAt: serverTimestamp() });
}

test('only owners write profiles; no tokens/photos/email in public schema', async () => {
  await assertSucceeds(publish('alice'));
  await assertFails(setDoc(doc(db('bob'), 'profiles', 'alice'), profile('alice')));
  await assertFails(setDoc(doc(db('alice'), 'profiles', 'alice'), { ...profile('alice'), spotifyToken: 'not-allowed' }));
  await assertFails(setDoc(doc(db('alice'), 'profiles', 'alice'), { ...profile('alice'), age: 17 }));
});
test('discovery requires authentication and an active-profile query', async () => {
  await publish('alice');
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'profiles', 'alice')));
  await assertSucceeds(getDocs(query(collection(db('bob'), 'profiles'), where('active', '==', true))));
  await assertFails(getDocs(collection(db('bob'), 'profiles')));
});
test('a user cannot forge someone else’s swipe or read their outgoing list', async () => {
  await publish('alice'); await publish('bob');
  await assertFails(setDoc(doc(db('bob'), 'swipes', 'alice', 'outgoing', 'bob'), {
    fromID: 'alice', toID: 'bob', decision: 'like', createdAt: serverTimestamp()
  }));
  await like('alice', 'bob');
  await assertFails(getDocs(collection(db('bob'), 'swipes', 'alice', 'outgoing')));
  await assertSucceeds(getDoc(doc(db('bob'), 'swipes', 'alice', 'outgoing', 'bob')));
});
test('one-sided likes cannot create matches or messages', async () => {
  await publish('alice'); await publish('bob'); await like('alice', 'bob');
  await assertFails(setDoc(doc(db('alice'), 'matches', 'alice__bob'), { members: ['alice', 'bob'], createdAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db('alice'), 'matches', 'alice__bob', 'messages', 'msg'), {
    senderID: 'alice', text: 'hello', sentAt: serverTimestamp()
  }));
});
test('mutual match members can exchange messages, outsiders cannot', async () => {
  await match();
  const path = ['matches', 'alice__bob', 'messages', 'msg'];
  await assertSucceeds(setDoc(doc(db('alice'), ...path), { senderID: 'alice', text: 'hello', sentAt: serverTimestamp() }));
  await assertSucceeds(getDoc(doc(db('bob'), ...path)));
  await assertFails(getDoc(doc(db('eve'), ...path)));
  await assertFails(setDoc(doc(db('eve'), 'matches', 'alice__bob', 'messages', 'eve-msg'), {
    senderID: 'eve', text: 'intrusion', sentAt: serverTimestamp()
  }));
  await assertFails(setDoc(doc(db('bob'), 'matches', 'alice__bob', 'messages', 'spoof'), {
    senderID: 'alice', text: 'spoof', sentAt: serverTimestamp()
  }));
  await assertFails(setDoc(doc(db('alice'), 'matches', 'alice__bob', 'messages', 'long'), {
    senderID: 'alice', text: 'x'.repeat(2001), sentAt: serverTimestamp()
  }));
});
test('hidden profiles disappear from discovery but stay readable to match partners', async () => {
  await match();
  await setDoc(doc(db('bob'), 'profiles', 'bob'), { ...profile('bob'), active: false });
  await assertFails(getDoc(doc(db('eve'), 'profiles', 'bob')));
  await assertSucceeds(getDoc(doc(db('alice'), 'profiles', 'bob')));
  const result = await getDocs(query(collection(db('eve'), 'profiles'), where('active', '==', true)));
  if (result.docs.some(d => d.id === 'bob')) throw new Error('Hidden profile leaked into discovery');
});

test('profile ownership includes updates and deletes; credential fields are rejected', async () => {
  const path = ['profiles', 'alice'];
  for (const field of ['email', 'password', 'accessToken', 'refreshToken', 'spotifyToken', 'clientSecret', 'private_key', 'photoURL']) {
    await assertFails(setDoc(doc(db('alice'), ...path), { ...profile('alice'), [field]: 'private-fixture' }));
  }
  await publish('alice');
  await assertFails(setDoc(doc(db('alice'), ...path), { email: 'private@example.test' }, { merge: true }));
  await assertFails(setDoc(doc(db('alice'), ...path), { ...profile('alice'), ownerID: 'bob' }));
  await assertFails(setDoc(doc(db('bob'), ...path), { bio: 'forged' }, { merge: true }));
  await assertFails(deleteDoc(doc(db('bob'), ...path)));
  await assertFails(deleteDoc(doc(env.unauthenticatedContext().firestore(), ...path)));
  await assertSucceeds(setDoc(doc(db('alice'), ...path), { bio: 'updated' }, { merge: true }));
  await assertSucceeds(deleteDoc(doc(db('alice'), ...path)));
});

test('artist and genre entries must be strings at every permitted position', async () => {
  for (const [field, size] of [['artists', 10], ['genres', 12]]) {
    await assertSucceeds(setDoc(doc(db('alice'), 'profiles', 'alice'), { ...profile('alice'), [field]: [] }));
    await assertSucceeds(setDoc(doc(db('alice'), 'profiles', 'alice'), { ...profile('alice'), [field]: Array(size).fill('Music') }));
    for (let index = 0; index < size; index++) {
      const entries = Array(size).fill('Music');
      entries[index] = { spotifyToken: 'private-fixture', email: 'private@example.test' };
      await assertFails(setDoc(doc(db('alice'), 'profiles', 'alice'), { ...profile('alice'), [field]: entries }));
    }
    for (const entry of [42, true, null]) {
      await assertFails(setDoc(doc(db('alice'), 'profiles', 'alice'), { ...profile('alice'), [field]: [entry] }));
    }
    await assertFails(setDoc(doc(db('alice'), 'profiles', 'alice'), { ...profile('alice'), [field]: Array(size + 1).fill('Music') }));
  }
});

test('unrelated and unauthenticated users cannot get or list private swipes', async () => {
  await publish('alice'); await publish('bob'); await like('alice', 'bob');
  const path = ['swipes', 'alice', 'outgoing', 'bob'];
  await assertSucceeds(getDoc(doc(db('alice'), ...path)));
  await assertSucceeds(getDoc(doc(db('bob'), ...path)));
  await assertSucceeds(getDocs(collection(db('alice'), 'swipes', 'alice', 'outgoing')));
  for (const outsider of [db('eve'), env.unauthenticatedContext().firestore()]) {
    await assertFails(getDoc(doc(outsider, ...path)));
    await assertFails(getDocs(collection(outsider, 'swipes', 'alice', 'outgoing')));
    await assertFails(setDoc(doc(outsider, ...path), {
      fromID: 'alice', toID: 'bob', decision: 'like', createdAt: serverTimestamp()
    }));
  }
  await assertFails(setDoc(doc(db('alice'), 'swipes', 'alice', 'outgoing', 'alice'), {
    fromID: 'alice', toID: 'alice', decision: 'like', createdAt: serverTimestamp()
  }));
});

test('passes, inactive profiles, outsiders and malformed IDs cannot create matches', async () => {
  await publish('alice'); await publish('bob'); await like('alice', 'bob');
  await setDoc(doc(db('bob'), 'swipes', 'bob', 'outgoing', 'alice'), {
    fromID: 'bob', toID: 'alice', decision: 'pass', createdAt: serverTimestamp()
  });
  const data = () => ({ members: ['alice', 'bob'], createdAt: serverTimestamp() });
  await assertFails(setDoc(doc(db('alice'), 'matches', 'alice__bob'), data()));
  await like('bob', 'alice');
  await assertFails(setDoc(doc(db('eve'), 'matches', 'alice__bob'), data()));
  await assertFails(setDoc(doc(db('alice'), 'matches', 'arbitrary'), data()));
  await assertFails(setDoc(doc(db('alice'), 'matches', 'alice__alice'), {
    members: ['alice', 'alice'], createdAt: serverTimestamp()
  }));
  await setDoc(doc(db('bob'), 'profiles', 'bob'), { ...profile('bob'), active: false });
  await assertFails(setDoc(doc(db('alice'), 'matches', 'alice__bob'), data()));
  await assertFails(like('alice', 'bob'));
});

test('match queries require membership and matches cannot be edited or deleted', async () => {
  await match();
  const path = ['matches', 'alice__bob'];
  await assertSucceeds(getDocs(query(collection(db('bob'), 'matches'), where('members', 'array-contains', 'bob'))));
  await assertFails(getDocs(collection(db('bob'), 'matches')));
  await assertFails(getDoc(doc(db('eve'), ...path)));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), ...path)));
  await assertFails(setDoc(doc(db('alice'), ...path), { members: ['alice', 'eve'], createdAt: serverTimestamp() }));
  await assertFails(deleteDoc(doc(db('alice'), ...path)));
});

test('message lists are private and messages immutable, including after hiding', async () => {
  await match();
  const messages = collection(db('alice'), 'matches', 'alice__bob', 'messages');
  const message = doc(messages, 'immutable');
  await setDoc(message, { senderID: 'alice', text: 'hello', sentAt: serverTimestamp() });
  await assertSucceeds(getDocs(messages));
  for (const outsider of [db('eve'), env.unauthenticatedContext().firestore()]) {
    await assertFails(getDocs(collection(outsider, 'matches', 'alice__bob', 'messages')));
    await assertFails(setDoc(doc(outsider, 'matches', 'alice__bob', 'messages', 'intrusion'), {
      senderID: 'eve', text: 'intrusion', sentAt: serverTimestamp()
    }));
  }
  await assertFails(setDoc(message, { senderID: 'alice', text: 'edited', sentAt: serverTimestamp() }));
  await assertFails(deleteDoc(message));
  await setDoc(doc(db('bob'), 'profiles', 'bob'), { ...profile('bob'), active: false });
  await assertSucceeds(getDocs(messages));
  await assertSucceeds(setDoc(doc(db('bob'), 'matches', 'alice__bob', 'messages', 'hidden'), {
    senderID: 'bob', text: 'still here', sentAt: serverTimestamp()
  }));
});

test('clients cannot forge timestamps or send empty messages', async () => {
  await publish('alice'); await publish('bob'); await like('alice', 'bob'); await like('bob', 'alice');
  await assertFails(setDoc(doc(db('alice'), 'matches', 'alice__bob'), {
    members: ['alice', 'bob'], createdAt: Timestamp.fromMillis(0)
  }));
  await setDoc(doc(db('alice'), 'matches', 'alice__bob'), { members: ['alice', 'bob'], createdAt: serverTimestamp() });
  await assertFails(setDoc(doc(db('alice'), 'swipes', 'alice', 'outgoing', 'bob'), {
    fromID: 'alice', toID: 'bob', decision: 'like', createdAt: Timestamp.fromMillis(0)
  }));
  await assertFails(setDoc(doc(db('alice'), 'matches', 'alice__bob', 'messages', 'old'), {
    senderID: 'alice', text: 'hello', sentAt: Timestamp.fromMillis(0)
  }));
  await assertFails(setDoc(doc(db('alice'), 'matches', 'alice__bob', 'messages', 'empty'), {
    senderID: 'alice', text: '', sentAt: serverTimestamp()
  }));
});
