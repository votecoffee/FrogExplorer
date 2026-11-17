import json
import math
import unittest
from frog_explorer import protocol


class ProtocolTests(unittest.TestCase):
    def state(self):
        return dict(v=1, kind="state", session="test", seq=0, time=1.25,
                    position=[1,2,3], forward=[0,0,1], up=[0,1,0])

    def test_round_trip(self):
        self.assertEqual(protocol.decode_state(protocol.encode(self.state())), self.state())

    def test_frame_conversion_is_right_handed(self):
        position, q = protocol.pose(self.state())
        self.assertEqual(position, (-3., -1., 2.))
        self.assertAlmostEqual(abs(q[2]), 1.)
        self.assertAlmostEqual(q[3], 0.)

    def test_climbing_orientation_is_normalized(self):
        state=self.state();state["forward"]=[0,1,0];state["up"]=[0,0,1]
        _, q=protocol.pose(state)
        self.assertAlmostEqual(sum(x*x for x in q), 1.)

    def test_zero_orientation_is_rejected(self):
        state=self.state();state["up"]=[0,0,0]
        with self.assertRaises(ValueError):protocol.pose(state)

    def test_nonfinite_values_are_rejected(self):
        state=self.state();state["position"]=[float("nan"),0,0]
        with self.assertRaises(ValueError):protocol.decode_state(json.dumps(state).encode())
        with self.assertRaises(ValueError):protocol.encode(state)

    def test_invalid_vectors_are_rejected(self):
        with self.assertRaises(ValueError):protocol.finite_vector([1,2],3)
        with self.assertRaises(ValueError):protocol.finite_vector([float("inf")],1)

    def test_invalid_versions_and_sequences_are_rejected(self):
        for key,value in [("v",2),("seq",-1),("seq",True),("session","")]:
            state=self.state();state[key]=value
            with self.assertRaises(ValueError):protocol.decode_state(protocol.encode(state))

    def test_velocity_units_sign_and_limits(self):
        packet=protocol.velocity_packet([.3,.2,.1],.5)
        self.assertEqual(packet["forward"],.3)
        self.assertEqual(packet["strafe"],-.2)
        self.assertEqual(packet["vertical"],.1)
        self.assertEqual(packet["yaw"],.5)
        self.assertLessEqual(protocol.velocity_packet([10,10,10],10)["ttl"],.5)

    def test_oversized_packet_is_rejected(self):
        with self.assertRaises(ValueError):protocol.decode_state(b" "*32769)

    def test_external_joy_dpad_and_y_direction(self):
        buttons=[0]*15;buttons[11]=1;buttons[14]=1
        move,aux=protocol.joy_axes([0.,0.,0.,.5],buttons)
        self.assertEqual(move,[1.,-1.]);self.assertEqual(aux,[0.,.5])
        move,aux=protocol.joy_axes([0.,1.,0.,1.],[0]*15,True)
        self.assertEqual(move,[0.,-1.]);self.assertEqual(aux,[0.,-1.])

    def test_named_travel_has_no_executable_path(self):
        self.assertEqual(protocol.travel_packet("helsinki_senate_square"),
                         {"kind": "travel", "place_id": "helsinki_senate_square"})
        for request in ("", "../world.glb", "https://example.com", "city name", 42):
            with self.assertRaises(ValueError):protocol.travel_packet(request)

    def test_travel_aliases_and_standard_gamepad_buttons(self):
        for request in ("random", "home", "cancel"):
            self.assertEqual(protocol.travel_packet(request),
                             {"kind": "action", "action": "travel_" + request})
        self.assertEqual(protocol.BUTTON_ACTIONS[4], "travel_random")
        self.assertEqual(protocol.BUTTON_ACTIONS[8], "travel_menu")

    def test_place_epoch_does_not_change_local_pose_conversion(self):
        state=self.state()
        state.update(place_id="helsinki_senate_square", map_epoch=3,
                     geographic_anchor={"horizontal_crs":"EPSG:3879"})
        decoded=protocol.decode_state(protocol.encode(state))
        self.assertEqual(decoded["map_epoch"],3)
        self.assertEqual(protocol.pose(decoded),protocol.pose(self.state()))

    def test_resize_trigger_direction_deadzone_and_cancellation(self):
        self.assertEqual(protocol.joy_size_axis([0,0,0,0,1,0]),1.)
        self.assertEqual(protocol.joy_size_axis([0,0,0,0,0,1]),-1.)
        self.assertEqual(protocol.joy_size_axis([0,0,0,0,1,1]),0.)
        self.assertEqual(protocol.joy_size_axis([0,0,0,0,.03,.02]),0.)
        self.assertEqual(protocol.joy_size_axis([0,0,0,0]),0.)
        with self.assertRaises(ValueError):protocol.joy_size_axis([0,0,0,0,float('nan'),0])

    def test_size_packet_limits(self):
        for factor in [.25,1,4,16]:
            self.assertEqual(protocol.size_packet(factor),{"kind":"size","factor":float(factor)})
        for factor in [0,-1,.249,16.01,float('inf'),float('nan'),True]:
            with self.assertRaises(ValueError):protocol.size_packet(factor)

    def test_input_axes_accept_legacy_and_resize_layout(self):
        self.assertEqual(len(protocol.input_axes([0]*4)),4)
        self.assertEqual(len(protocol.input_axes([0]*6)),6)
        with self.assertRaises(ValueError):protocol.input_axes([0]*5)


if __name__ == "__main__":unittest.main()
