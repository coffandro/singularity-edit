using Singularity;
using Singularity.Apps;

int main (string[] args) {
    var app = new EditApp ();
    return app.run (args);
}
