# syncstuff

Syncs stuff over FTP.

Keeps a local index of file sizes and modification dates, and pushes changed files to an FTP server.

## How to use

1. Run the program once to generate a `credentials.json`
2. Edit the file and enter FTP address, port, login, password and base directory
3. Run the program by specifying a path or have it infer the default path "`.`".
4. See `--help` for more options

## Roadmap

* get it to work properly
* error handling

## License

This project is licensed under the Boost Software License 1.0 - see the [LICENSE_1_0.txt](LICENSE_1_0.txt) file for details.
