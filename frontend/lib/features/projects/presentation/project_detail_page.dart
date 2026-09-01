import 'package:flutter/material.dart';

import '../project_workspace.dart';
import 'project_workspace_page.dart';

class ProjectDetailPage extends StatelessWidget {
  const ProjectDetailPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) => ProjectWorkspacePage(
        target: ProjectWorkspaceTarget.project(projectId),
      );
}
