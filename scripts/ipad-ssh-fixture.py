#!/usr/bin/env python3
"""Loopback-only SSH echo fixture for gtermUITests. Requires paramiko.

Accepts only synthetic test/test2 users with password 'test'. Reports received
bytes and PTY sizes so hardware-key routing and resize can be verified without
contacting a real host. This is an echo channel, not a shell.
"""
import socket
import threading

import paramiko


class Server(paramiko.ServerInterface):
    def check_auth_password(self, username, password):
        if username in ("test", "test2") and password == "test":
            return paramiko.AUTH_SUCCESSFUL
        return paramiko.AUTH_FAILED

    def get_allowed_auths(self, username):
        return "password"

    def check_channel_request(self, kind, channel_id):
        if kind == "session":
            return paramiko.OPEN_SUCCEEDED
        return paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def check_channel_pty_request(self, channel, term, width, height, *args):
        print("PTY", width, height, flush=True)
        return True

    def check_channel_window_change_request(self, channel, width, height, *args):
        print("RESIZE", width, height, flush=True)
        return True

    def check_channel_shell_request(self, channel):
        return True

    def check_channel_env_request(self, *args):
        return True


def serve_client(sock, host_key):
    transport = paramiko.Transport(sock)
    try:
        transport.add_server_key(host_key)
        transport.start_server(server=Server())
        channel = transport.accept(20)
        if channel is None:
            return
        for index in range(120):
            channel.sendall(f"Fixture line {index:03}: Magic Keyboard selection and scrolling test\r\n".encode())
        channel.sendall(b"\r\ngterm Magic Keyboard SSH fixture\r\n$ ")
        while data := channel.recv(4096):
            print("INPUT", data.hex(), flush=True)
            channel.sendall(data)
    except (EOFError, OSError, paramiko.SSHException) as error:
        print(type(error).__name__, flush=True)
    finally:
        transport.close()


if __name__ == "__main__":
    host_key = paramiko.ECDSAKey.generate(bits=256)
    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", 62222))
        listener.listen()
        print("READY on 127.0.0.1:62222", flush=True)
        while True:
            client, _ = listener.accept()
            threading.Thread(target=serve_client, args=(client, host_key), daemon=True).start()
