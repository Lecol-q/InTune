import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, getDocs, collection, query, where, serverTimestamp } from 'firebase/firestore';

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
