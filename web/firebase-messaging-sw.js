/* Firebase Messaging SW (Web Push) */
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyDSKUx-6RtCuLiGcnMVko0vAKvL9ik7hSI",
  authDomain: "locarb-attendance-v2.firebaseapp.com",
  projectId: "locarb-attendance-v2",
  storageBucket: "locarb-attendance-v2.firebasestorage.app",
  messagingSenderId: "953944468274",
  appId: "1:953944468274:web:319947e61b55f1341b452b"
});

const messaging = firebase.messaging();
