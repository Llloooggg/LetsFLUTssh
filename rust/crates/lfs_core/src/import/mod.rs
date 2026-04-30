//! Import orchestrators.
//!
//! Each submodule maps an external configuration source
//! (`~/.ssh/config`, exported `.lfs` archive, …) to a wire
//! preview the Dart UI renders before committing the import to
//! the local database. Submodules are pure-data oriented — they
//! read input, transform it, and return structured results.
//! Persistence belongs to the caller.

pub mod openssh_config;
