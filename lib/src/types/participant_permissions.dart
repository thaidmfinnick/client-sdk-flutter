// Copyright 2024 LiveKit, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:meta/meta.dart';

import 'package:livekit_client/src/proto/livekit_models.pbenum.dart';
import '../proto/livekit_models.pb.dart' as lk_models;

@immutable
class ParticipantPermissions {
  final bool canSubscribe;
  final bool canPublish;
  final bool canPublishData;
  final bool hidden;
  final bool canUpdateMetadata;
  final List<TrackSource> canPublishSources;

  const ParticipantPermissions({
    this.canSubscribe = false,
    this.canPublish = false,
    this.canPublishData = false,
    this.hidden = false,
    this.canUpdateMetadata = false,
    this.canPublishSources = const [],
  });
}

extension ParticipantPermissionExt on lk_models.ParticipantPermission {
  ParticipantPermissions toLKType() => ParticipantPermissions(
        canSubscribe: canSubscribe,
        canPublish: canPublish,
        canPublishData: canPublishData,
        hidden: hidden,
        canUpdateMetadata: canUpdateMetadata,
        canPublishSources: canPublishSources,
      );
}
