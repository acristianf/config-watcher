pub const r_errors = @This();

pub const WatcherConfErrors = error{
    HomeEnvNotSet,
    ContainerFolderNotSet,
};

pub const PathStructureError = error{
    RelativePathsNotSupported,
};
