pantheon_files_deps = [
    common_deps,
    pantheon_files_widgets_dep,
    unity_dep,
    plank_dep,
    zeitgeist_dep,
    project_config_dep,
]

pantheon_files_exec = executable (
    meson.project_name (),
    'main.vala',

    'Application.vala',
    'marlin-deep-count.vala',
    'ProgressUIHandler.vala',
    'QuicklistHandler.vala',
    'TextRenderer.vala',
    'ClipboardManager.vala',
    'IconRenderer.vala',
    'ZeitgeistManager.vala',

    'Dialogs/AbstractPropertiesDialog.vala',
    'Dialogs/ChooseAppDialog.vala',
    'Dialogs/PropertiesWindow.vala',
    'Dialogs/VolumePropertiesWindow.vala',

    'Utils/MimeActions.vala',
    'Utils/Permissions.vala',

    'View/Window.vala',
    'View/ColumnView.vala',
    'View/AbstractTreeView.vala',
    'View/IconView.vala',
    'View/ListView.vala',
    'View/DirectoryNotFound.vala',
    'View/AbstractDirectoryView.vala',
    'View/Window.vala',
    'View/ViewContainer.vala',
    'View/Browser.vala',
    'View/Sidebar.vala',
    'View/Slot.vala',
    'View/PrivacyModeOn.vala',
    'View/PopupMenuBuilder.vala',
    'View/Miller.vala',

    'View/Widgets/AbstractEditableLabel.vala',
    'View/Widgets/BreadcrumbsEntry.vala',
    'View/Widgets/DiskRenderer.vala',
    'View/Widgets/Label.vala',
    'View/Widgets/LocationBar.vala',
    'View/Widgets/MultiLineEditableLabel.vala',
    'View/Widgets/OverlayBar.vala',
    'View/Widgets/PermissionButton.vala',
    'View/Widgets/ProgressInfoWidget.vala',
    'View/Widgets/SingleLineEditableLabel.vala',
    'View/Widgets/TopMenu.vala',

    dependencies : [
        pantheon_files_deps,
        vala.find_library('marlin', dirs: meson.current_source_dir ()),
    ],
    install: true,
)

install_data (
    join_paths(meson.current_source_dir (), 'View', 'directory_view_popup.ui'),
    install_dir: ui_dir
)
