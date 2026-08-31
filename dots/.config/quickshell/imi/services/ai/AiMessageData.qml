import QtQuick;

/**
 * Represents a message in an AI conversation. (Kind of) follows the OpenAI API message structure.
 */
QtObject {
    property string role
    property string content
    property string rawContent
    property string fileMimeType
    property string fileUri
    property string localFilePath
    // Every attachment of the message; localFilePath stays as the first
    // for old sessions and single-file consumers.
    property list<string> localFilePaths: []
    property string model
    property bool thinking: true
    property bool done: false
    property var annotations: []
    property var annotationSources: []
    property list<string> searchQueries: []
    property string functionName
    property var functionCall
    property string functionResponse
    property bool functionPending: false
    // An image generation is in flight for this message: the transcript
    // shows an image-shaped skeleton until the sentinel resolves it.
    property bool generatingImage: false
    property bool visibleToUser: true
}
