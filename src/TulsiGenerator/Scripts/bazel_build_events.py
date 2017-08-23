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

"""Parses a stream of JSON build event protocol messages from a file."""

import json


class _FileLineReader(object):
  """Reads lines from a streaming file.

  This will repeatedly check the file for an entire line to read. It will
  buffer partial lines until they are completed.
  This is meant for files that are being modified by an long-living external
  program.
  """

  def __init__(self, file_obj):
    """Creates a new FileLineReader object.

    Args:
      file_obj: The file object to watch.

    Returns:
      A FileLineReader instance.
    """
    self._file_obj = file_obj
    self._buffer = []

  def check_for_changes(self):
    """Checks the file for any changes, returning the line read if any."""
    line = self._file_obj.readline()
    self._buffer.append(line)

    # Only parse complete lines.
    if not line.endswith('\n'):
      return None
    full_line = ''.join(self._buffer)
    del self._buffer[:]
    return full_line


class BazelBuildEvent(object):
  """Represents a Bazel Build Event.

  Public Properties:
    event_dict: the source dictionary for this event.
    id_as_string: 'id' in event_dict as a json string, if any.
    children_id_strings: list of all children id strings.
    stdout: stdout string, if any.
    stderr: stderr string, if any.
    files: list of file URIs.
  """

  def __init__(self, event_dict):
    """Creates a new BazelBuildEvent object.

    Args:
      event_dict: Dictionary representing a build event

    Returns:
      A BazelBuildEvent instance.
    """
    self.event_dict = event_dict
    self.id_as_string = (json.dumps(event_dict['id']) if 'id' in event_dict
                         else None)
    children = event_dict.get('children', [])
    self.children_id_strings = [json.dumps(x) for x in children]
    self._children_by_id_string = {}

    self.stdout = None
    self.stderr = None
    self.files = []
    if 'progress' in event_dict:
      self._update_fields_for_progress(event_dict['progress'])
    if 'namedSetOfFiles' in event_dict:
      self._update_fields_for_named_set_of_files(event_dict['namedSetOfFiles'])

  def _update_fields_for_progress(self, progress_dict):
    self.stdout = progress_dict.get('stdout')
    self.stderr = progress_dict.get('stderr')

  def _update_fields_for_named_set_of_files(self, named_set):
    files = named_set.get('files', [])
    for file_obj in files:
      uri = file_obj.get('uri', '')
      if uri.startswith('file://'):
        self.files.append(uri[7:])

  def is_resolved(self):
    """Returns True iff this build event is considered resolved.

    This means all of it's children (and their children, recursively) are
    present in the tree.
    """
    children_id_strings = self.children_id_strings
    if not children_id_strings:
      return True
    children_by_id = self._children_by_id_string
    for child_id in children_id_strings:
      if child_id not in children_by_id:
        return False
      if not children_by_id[child_id].is_resolved():
        return False
    return True

  def resolved_children_events(self):
    """Returns all of the currently resolved child BazelBuildEvents."""
    events = []
    children_id_strings = self.children_id_strings
    if not children_id_strings:
      return events
    children_by_id = self._children_by_id_string
    for child_id in children_id_strings:
      if child_id in children_by_id:
        events.append(children_by_id[child_id])
    return events

  def insert_child(self, child_event):
    """Inserts the specified BazelBuildEvent as a child."""
    self._children_by_id_string[child_event.id_as_string] = child_event


class _BazelBuildEventTree(object):
  """Class to help resolve a structured tree from a stream of Build Events."""

  def __init__(self, root_build_event, warning_handler):
    """Creates a new BazelBuildEventTree object.

    Args:
      root_build_event: The root BazelBuildEvent
      warning_handler: Handler function for warnings accepting a single string.

    Returns:
      A BazelBuildEventTree instance.
    """
    self.root_build_event = root_build_event
    self.warning_handler = warning_handler
    self.event_parents_by_id = {}
    self._index_children_of_event(self.root_build_event)

  def insert_child(self, build_event):
    """Inserts the BazelBuildEvent into the tree."""
    self._attach_child_event_to_parent(build_event)
    self._index_children_of_event(build_event)

  def is_complete(self):
    """Returns True iff the root of the tree is considered resolved.

    This means all of it's children (and their children, recursively) are
    present in the tree.
    """
    return self.root_build_event.is_resolved()

  def _attach_child_event_to_parent(self, build_event):
    """Attach a build_event to its proper parent using our parent index."""
    event_id = build_event.id_as_string
    if not event_id:
      event_str = json.dumps(build_event.event_dict)
      self._warn('BazelBuildEvent %s does not have an id!' % event_str)
      return
    parent = self.event_parents_by_id.get(event_id, None)
    if not parent:
      self._warn('Unable to find parent for BazelBuildEvent %s!' % event_id)
      return
    parent.insert_child(build_event)

  def _index_children_of_event(self, build_event):
    """Index the children of build_event so we can easily attach them later."""
    event_parents_by_id = self.event_parents_by_id
    for child_id in build_event.children_id_strings:
      event_parents_by_id[child_id] = build_event

  def _warn(self, msg):
    """Logs the warning to the warning_handler if it exists."""
    if self.warning_handler:
      self.warning_handler(msg)


class BazelBuildEventsWatcher(object):
  """Watches a build events JSON file."""

  def __init__(self, json_file, warning_handler=None):
    """Creates a new BazelBuildEventsWatcher object.

    Args:
      json_file: The JSON file object to watch.
      warning_handler: Handler function for warnings accepting a single string.

    Returns:
      A BazelBuildEventsWatcher instance.
    """
    self.file_reader = _FileLineReader(json_file)
    self.build_event_tree = None
    self.warning_handler = warning_handler

  def check_for_new_events(self):
    """Checks the file for new BazelBuildEvents.

    Returns:
      A list of all new BazelBuildEvents.
    """
    new_events = []
    while True:
      line = self.file_reader.check_for_changes()
      if not line:
        break
      build_event_dict = json.loads(line)
      build_event = BazelBuildEvent(build_event_dict)
      if not self.build_event_tree:
        handler = self.warning_handler
        self.build_event_tree = _BazelBuildEventTree(build_event, handler)
      else:
        self.build_event_tree.insert_child(build_event)
      new_events.append(build_event)
    return new_events

  def is_build_complete(self):
    tree = self.build_event_tree
    return tree.is_complete() if tree else False
