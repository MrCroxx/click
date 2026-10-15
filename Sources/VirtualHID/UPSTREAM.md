# Virtual HID client

The unmodified client headers in `vendor/pqrs/karabiner` are from
[pqrs-org/Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)
commit `ac836ed8a974cd5182495251855cabdb762f50cb` (package 8.6.0, driver 1.8.0,
client protocol 7). Its transitive header dependencies are copied from the same
commit's `vendor/vendor/include`. Unused boost-ut, nlohmann-json and spdlog trees
are omitted. No driver binary is bundled or downloaded during builds.

Protocol 7 is also used by package 8.5.0. The official client handles framing,
heartbeats, acknowledgements, and version rejection. A ready notification is
required before Click opens physical keyboards with SeizeDevice.

Header license notices are retained. `Licenses` contains Boost 1.0 (pqrs and
Asio), MIT (GSL, type_safe, debug_assert), and the nod license. The upstream
project-level public-domain license is in `LICENSE.md`; it does not replace
individual dependency licenses. `VirtualHID.cpp` and the public C header are
Click's MIT-licensed adapter.

The pinned upstream client uses C++23. Updating it requires reviewing protocol
and deployment compatibility and testing the matching official driver package.
