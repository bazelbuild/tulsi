# Copyright 2017 The Tulsi Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Test for bazel_build_events.py."""

import io
import json
import unittest

import bazel_build_events

ROOT_ID = {'foo': 'bar'}
CHILD_ID = {'foo': 'child'}
GRANDCHILD_ID = {'foo': 'grandchild'}

ROOT_EVENT_DICT = {
    'id': ROOT_ID,
    'children': [CHILD_ID],
    'progress': {
        'stdout': 'Hello',
        'stderr': 'World',
    },
    'namedSetOfFiles': {
        'files': [{'uri': 'file:///dir/file.txt'}],
    },
}

CHILD_EVENT_DICT = {
    'id': CHILD_ID,
    'progress': {
        'stderr': 'Hello!',
    },
}

CHILD_WITHOUT_ID_EVENT_DICT = {
    'progress': {
        'stderr': 'Hello!',
    },
}

CHILD_EVENT_WITH_CHILD_DICT = {
    'id': CHILD_ID,
    'children': [{'foo': 'grandchild'}],
}

GRANDCHILD_EVENT_DICT = {
    'id': GRANDCHILD_ID,
    'progress': {
        'stderr': 'Hello from the grandchild!',
    },
}


class TestFileLineReader(unittest.TestCase):

  def testMultiLine(self):
    test_file = io.StringIO()
    test_file.write(u'First Line.\nSecond Line.\nThird Line.\n')
    test_file.seek(0)
    reader = bazel_build_events._FileLineReader(test_file)
    self.assertEqual(reader.check_for_changes(), 'First Line.\n')
    self.assertEqual(reader.check_for_changes(), 'Second Line.\n')
    self.assertEqual(reader.check_for_changes(), 'Third Line.\n')
    self.assertIsNone(reader.check_for_changes())

  def testLineRescans(self):
    test_file = io.StringIO()
    reader = bazel_build_events._FileLineReader(test_file)
    self.assertIsNone(reader.check_for_changes())
    test_file.write(u'Line')
    test_file.seek(0)
    self.assertIsNone(reader.check_for_changes())
    test_file.seek(0, 2)
    partial_pos = test_file.tell()
    test_file.write(u'!\n')
    test_file.seek(partial_pos)
    self.assertEqual(reader.check_for_changes(), 'Line!\n')
    self.assertIsNone(reader.check_for_changes())


class TestBazelBuildEvents(unittest.TestCase):

  def testBuildEventParsing(self):
    event_dict = ROOT_EVENT_DICT
    build_event = bazel_build_events.BazelBuildEvent(event_dict)
    self.assertEqual(build_event.stdout, 'Hello')
    self.assertEqual(build_event.stderr, 'World')
    self.assertEqual(build_event.files, ['/dir/file.txt'])


class TestBazelBuildEventsWatcher(unittest.TestCase):

  def testWatcherBuildEvent(self):
    test_file = io.StringIO()
    watcher = bazel_build_events.BazelBuildEventsWatcher(test_file)
    test_file.write(json.dumps(ROOT_EVENT_DICT) + u'\n')
    test_file.seek(0)
    new_events = watcher.check_for_new_events()
    self.assertEqual(len(new_events), 1)
    build_event = new_events[0]
    self.assertEqual(build_event.stdout, 'Hello')
    self.assertEqual(build_event.stderr, 'World')
    self.assertEqual(build_event.files, ['/dir/file.txt'])

if __name__ == '__main__':
  unittest.main()
