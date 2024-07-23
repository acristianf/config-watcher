pub const r_errors = @This();

pub const WatcherConfErrors = error{
    HomeEnvNotSet,
    ContainerFolderNotSet,
    ConfigFileSizeTooLong,
};

pub const PathStructureError = error{
    RelativePathsNotSupported,
};

pub const GeneralErrors = error{GitError};
